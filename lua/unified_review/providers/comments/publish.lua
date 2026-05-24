local comment_status = require("unified_review.domain.comment_status")
local comment_target = require("unified_review.domain.comment_target")
local github_pr_provider = require("unified_review.providers.diff.github_pr")
local graphql = require("unified_review.integrations.github_graphql")
local review_thread = require("unified_review.domain.review_thread")
local session_store = require("unified_review.persist.session_store")

local M = {}

local function github_opts(session)
	local github_cfg = require("unified_review.config").options.github or {}
	return {
		cwd = session and session.target and (session.target.source_root or session.target.cwd or session.target.root),
		command = github_cfg.transport_command,
		timeout = github_cfg.timeout,
	}
end

local function ensure_pending_review(session)
	session.metadata = session.metadata or {}
	session.metadata.github = session.metadata.github or {}
	if session.metadata.github.pending_review_id then
		return session.metadata.github.pending_review_id, nil
	end
	local review_id, err = graphql.create_pending_review(session.target, github_opts(session))
	if not review_id then
		return nil, err
	end
	session.metadata.github.pending_review_id = review_id
	pcall(session_store.write, session)
	return review_id, nil
end

local function pr_identity(session)
	local target = session and session.target or {}
	return {
		id = session and session.id,
		owner = target.owner,
		repo = target.repo,
		number = target.number,
		url = target.url,
		pull_request_id = target.pull_request_id,
		pending_review_id = session
			and session.metadata
			and session.metadata.github
			and session.metadata.github.pending_review_id,
	}
end

local function associate(local_session, github_session)
	local_session.metadata = local_session.metadata or {}
	github_session.metadata = github_session.metadata or {}
	local_session.metadata.github_pr_session = pr_identity(github_session)
	github_session.metadata.local_session = {
		id = local_session.id,
		kind = local_session.kind,
		root = local_session.target and local_session.target.root,
	}
	pcall(session_store.write, local_session)
	pcall(session_store.write, github_session)
end

local function file_matches(file, path)
	return file and path and (file.path == path or file.old_path == path)
end

local function find_pr_file(github_session, path)
	for _, file in ipairs(github_session.files or {}) do
		if file_matches(file, path) then
			return file
		end
	end
	return nil
end

local function line_on_side(diff_line, side)
	if side == "left" then
		if diff_line.kind == "added" then
			return nil
		end
		return diff_line.old_line
	end
	if diff_line.kind == "deleted" then
		return nil
	end
	return diff_line.new_line
end

local function has_diff_coordinate(file, side, line_number)
	for _, hunk in ipairs(file.hunks or {}) do
		for _, diff_line in ipairs(hunk.lines or {}) do
			if line_on_side(diff_line, side) == line_number then
				return true
			end
		end
	end
	return false
end

local function normalize_path(file)
	return file.path or file.old_path
end

local function exact_target(file, target)
	if target.kind == "file" then
		return nil, "GitHub pending review API does not support file-level comments"
	end
	if target.kind == "range" and target.side ~= target.start_side then
		return nil, "GitHub range comments must stay on one diff side"
	end
	local side = target.kind == "range" and target.side or target.side
	if not side then
		return nil, "comment target is missing a diff side"
	end
	local start_line = target.kind == "range" and target.start_line or target.line
	local end_line = target.line
	if not start_line or not end_line then
		return nil, "comment target is missing a line number"
	end
	if start_line > end_line then
		start_line, end_line = end_line, start_line
	end
	for line = start_line, end_line do
		if not has_diff_coordinate(file, side, line) then
			return nil, "target line is not present in the GitHub PR diff"
		end
	end
	if target.kind == "range" or start_line ~= end_line then
		return {
			kind = "range",
			path = normalize_path(file),
			start_side = side,
			start_line = start_line,
			side = side,
			line = end_line,
		},
			nil
	end
	return { kind = "line", path = normalize_path(file), side = side, line = end_line }, nil
end

local function side_entries(file, side)
	local entries = {}
	for _, hunk in ipairs(file.hunks or {}) do
		for _, diff_line in ipairs(hunk.lines or {}) do
			local line_number = line_on_side(diff_line, side)
			if line_number then
				table.insert(entries, { line = line_number, text = diff_line.text or "" })
			end
		end
	end
	return entries
end

local function anchor_exact_target(file, target, anchor)
	if not anchor or not anchor.selected or #anchor.selected == 0 then
		return nil, "target line is not present in the GitHub PR diff"
	end
	local side = anchor.side or target.side or target.start_side or "right"
	local entries = side_entries(file, side)
	local selected = anchor.selected
	local matches = {}
	for index = 1, #entries - #selected + 1 do
		local ok = true
		for offset = 1, #selected do
			if entries[index + offset - 1].text ~= selected[offset] then
				ok = false
				break
			end
		end
		if ok then
			table.insert(matches, entries[index].line)
		end
	end
	if #matches == 0 then
		return nil, "anchor excerpt is not present in the GitHub PR diff"
	end
	if #matches > 1 then
		return nil, "anchor excerpt matched multiple GitHub PR diff locations"
	end
	local start_line = matches[1]
	if #selected == 1 then
		return { kind = "line", path = normalize_path(file), side = side, line = start_line }, nil
	end
	return {
		kind = "range",
		path = normalize_path(file),
		start_side = side,
		start_line = start_line,
		side = side,
		line = start_line + #selected - 1,
	},
		nil
end

function M.map_target(github_session, thread)
	local target = thread and thread.target
	if not target or not target.path then
		return nil, "comment target is missing"
	end
	local file = find_pr_file(github_session, target.path)
	if not file then
		return nil, "file is not present in the GitHub PR diff"
	end
	local mapped, exact_reason = exact_target(file, target)
	if mapped then
		return mapped, nil
	end
	local anchor = thread.metadata and thread.metadata.anchor
	local anchor_mapped, anchor_reason = anchor_exact_target(file, target, anchor)
	if anchor_mapped then
		return anchor_mapped, nil
	end
	return nil, anchor_reason or exact_reason
end

local function local_drafts(thread)
	local drafts = {}
	for _, comment in ipairs((thread and thread.comments) or {}) do
		if comment_status.is_local_draft(comment) then
			table.insert(drafts, comment)
		end
	end
	return drafts
end

local function mark_failed(thread, comments, reason)
	thread.metadata = thread.metadata or {}
	thread.metadata.publish = { state = "failed", reason = reason }
	for _, comment in ipairs(comments or {}) do
		comment.state = "publish_failed"
		comment.metadata = comment.metadata or {}
		comment.metadata.publish = { state = "failed", reason = reason }
	end
end

local function mark_published(thread, local_comment, remote_comment, review_id, remote_thread)
	local_comment.state = "draft"
	local_comment.metadata = local_comment.metadata or {}
	local_comment.metadata.github = remote_comment and remote_comment.metadata and remote_comment.metadata.github
		or remote_comment
		or { id = remote_comment and remote_comment.id }
	local_comment.metadata.github_pending_review_id = review_id
	local_comment.metadata.publish = {
		state = "published",
		github_thread_id = remote_thread and remote_thread.id,
		github_comment_id = remote_comment and remote_comment.id,
	}
	thread.metadata = thread.metadata or {}
	thread.metadata.publish = vim.tbl_extend("force", thread.metadata.publish or {}, {
		state = "published",
		github_thread_id = remote_thread and remote_thread.id,
		github_target = remote_thread and remote_thread.target,
	})
end

local function open_github_session(local_session, opts)
	opts = opts or {}
	if opts.github_session then
		return opts.github_session, nil
	end
	local associated = local_session.metadata and local_session.metadata.github_pr_session or {}
	local pr_ref = opts.pr_ref or opts.number_or_url or associated.url or associated.number
	local target = require("unified_review.domain.review_target").github_pr({
		cwd = local_session.target and (local_session.target.cwd or local_session.target.root),
		root = local_session.target and local_session.target.root,
		number = tonumber(pr_ref) or associated.number,
		url = tonumber(pr_ref) and nil or pr_ref,
	})
	return github_pr_provider.open(target)
end

function M.publish(local_session, opts)
	opts = opts or {}
	if not local_session then
		return nil, { message = "No local review session" }
	end
	if local_session.kind == "github_pr" then
		return nil, { message = "Use publish-drafts in GitHub PR sessions" }
	end
	local github_session, open_err = open_github_session(local_session, opts)
	if not github_session then
		return nil, open_err
	end
	local review_id, review_err = ensure_pending_review(github_session)
	if not review_id then
		return nil, review_err
	end
	local report = {
		review_id = review_id,
		github_session = github_session,
		successes = {},
		failures = {},
		skipped = {},
	}
	for _, thread in ipairs(local_session.threads or {}) do
		if review_thread.is_exported(thread) then
			local drafts = local_drafts(thread)
			if #drafts == 0 then
				table.insert(report.skipped, { thread = thread, reason = "no local draft comments" })
			else
				local mapped, map_reason = M.map_target(github_session, thread)
				if not mapped then
					local reason = map_reason or "target does not map to GitHub PR diff coordinates"
					mark_failed(thread, drafts, reason)
					table.insert(report.failures, { thread = thread, reason = reason, comments = #drafts })
				else
					local remote_thread = nil
					local remote_thread_id = thread.metadata
						and thread.metadata.publish
						and thread.metadata.publish.github_thread_id
					for index, comment in ipairs(drafts) do
						if index == 1 and not remote_thread_id then
							local created, err =
								graphql.add_thread(review_id, mapped, comment.body, github_opts(github_session))
							if not created then
								mark_failed(
									thread,
									{ comment },
									err and err.message or "failed to create GitHub thread"
								)
								table.insert(report.failures, {
									thread = thread,
									comment = comment,
									reason = err and err.message or "failed to create GitHub thread",
								})
								break
							end
							remote_thread = created
							remote_thread_id = created.id
							mark_published(
								thread,
								comment,
								created.comments and created.comments[1],
								review_id,
								created
							)
							table.insert(report.successes, { thread = thread, comment = comment, target = mapped })
						else
							local reply, err =
								graphql.add_reply(remote_thread_id, comment.body, github_opts(github_session))
							if not reply then
								mark_failed(thread, { comment }, err and err.message or "failed to create GitHub reply")
								table.insert(report.failures, {
									thread = thread,
									comment = comment,
									reason = err and err.message or "failed to create GitHub reply",
								})
							else
								remote_thread = remote_thread or { id = remote_thread_id, target = mapped }
								mark_published(thread, comment, reply, review_id, remote_thread)
								table.insert(report.successes, { thread = thread, comment = comment, target = mapped })
							end
						end
					end
				end
			end
		else
			table.insert(report.skipped, { thread = thread, reason = "thread is not marked for export" })
		end
	end
	associate(local_session, github_session)
	report.association = local_session.metadata.github_pr_session
	pcall(session_store.write, local_session)
	pcall(session_store.write, github_session)
	return report, nil
end

function M.format_report(report)
	report = report or {}
	local lines = {
		"# Draft publishing",
		"",
		string.format("Pending review: %s", tostring(report.review_id or "unknown")),
		string.format("Published: %d", #(report.successes or {})),
		string.format("Failed: %d", #(report.failures or {})),
		string.format("Skipped: %d", #(report.skipped or {})),
	}
	if #(report.successes or {}) > 0 then
		table.insert(lines, "")
		table.insert(lines, "## Published")
		for _, success in ipairs(report.successes) do
			table.insert(lines, "- " .. comment_target.label(success.target))
		end
	end
	if #(report.failures or {}) > 0 then
		table.insert(lines, "")
		table.insert(lines, "## Failed")
		for _, failure in ipairs(report.failures) do
			local label = failure.thread and failure.thread.target and comment_target.label(failure.thread.target)
				or "unknown target"
			table.insert(lines, string.format("- %s: %s", label, failure.reason or "unknown reason"))
		end
	end
	if #(report.skipped or {}) > 0 then
		table.insert(lines, "")
		table.insert(lines, "## Skipped")
		for _, skipped in ipairs(report.skipped) do
			local label = skipped.thread and skipped.thread.target and comment_target.label(skipped.thread.target)
				or "unknown target"
			table.insert(lines, string.format("- %s: %s", label, skipped.reason or "skipped"))
		end
	end
	return lines
end

return M
