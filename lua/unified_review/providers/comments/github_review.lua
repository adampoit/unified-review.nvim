local comment_status = require("unified_review.domain.comment_status")
local graphql = require("unified_review.integrations.github_graphql")
local local_store = require("unified_review.providers.comments.local_store")
local review_thread = require("unified_review.domain.review_thread")
local session_store = require("unified_review.persist.session_store")

local M = {}

local function opts_for(session)
	local github_cfg = require("unified_review.config").options.github or {}
	local target = session and session.target or {}
	return {
		cwd = target.source_root or target.cwd or target.root,
		command = github_cfg.transport_command,
		timeout = github_cfg.timeout,
	}
end

local function find_thread(session, thread_id)
	for index, thread in ipairs(session.threads or {}) do
		if thread.id == thread_id then
			return thread, index
		end
	end
	return nil, nil
end

local function is_remote_thread(thread)
	return thread and thread.metadata and thread.metadata.github ~= nil
end

local function draft_comments(thread, opts)
	opts = opts or {}
	local drafts = {}
	for index, comment in ipairs((thread and thread.comments) or {}) do
		if comment_status.is_draft(comment) then
			local include = true
			if opts.local_only then
				include = comment_status.is_local_draft(comment)
			elseif opts.remote_only then
				include = comment_status.is_remote_draft(comment)
			end
			if include then
				table.insert(drafts, { index = index, comment = comment })
			end
		end
	end
	return drafts
end

local function has_drafts(thread, opts)
	return #draft_comments(thread, opts) > 0
end

local function has_local_drafts(thread)
	return has_drafts(thread, { local_only = true })
end

local function is_local_worktree_session(session)
	local target = session and session.target or {}
	local metadata = session and session.metadata or {}
	return target.render_strategy == "local_worktree"
		or target.local_worktree == true
		or metadata.render_strategy == "local_worktree"
end

local function remote_diff_files(session)
	local metadata = session and session.metadata or {}
	if is_local_worktree_session(session) then
		return metadata.github_remote_files or {}
	end
	return session and session.files or {}
end

local function find_remote_file(session, path)
	for _, file in ipairs(remote_diff_files(session)) do
		if file.path == path or file.old_path == path then
			return file
		end
	end
	return nil
end

local function find_local_file(session, path)
	for _, file in ipairs((session and session.files) or {}) do
		if file.path == path or file.old_path == path then
			return file
		end
	end
	return nil
end

local function remote_line_text(file, side, line_number)
	if not file or not side or not line_number then
		return nil
	end
	for _, hunk in ipairs(file.hunks or {}) do
		for _, line in ipairs(hunk.lines or {}) do
			if side == "left" and line.kind ~= "added" and line.old_line == line_number then
				return line.text
			end
			if side ~= "left" and line.kind ~= "deleted" and line.new_line == line_number then
				return line.text
			end
		end
	end
	return nil
end

local function target_remote_text(session, target)
	if not target or target.kind == "file" then
		return nil, { message = "GitHub file-level PR comments are not supported by the GraphQL review thread API" }
	end
	local file = find_remote_file(session, target.path)
	if not file then
		return nil, { message = "`" .. tostring(target.path) .. "` is not present in the remote PR diff yet" }
	end
	local side = target.side or target.start_side or "right"
	local start_line = target.start_line or target.line
	local end_line = target.line or target.start_line
	if not start_line or not end_line then
		return nil, { message = "comment target line is required" }
	end
	start_line, end_line = math.min(start_line, end_line), math.max(start_line, end_line)
	local lines = {}
	for line_number = start_line, end_line do
		local text = remote_line_text(file, side, line_number)
		if text == nil then
			return nil,
				{
					message = string.format(
						"%s:%d (%s side) is not present in the remote PR diff yet",
						tostring(target.path),
						line_number,
						side == "left" and "left" or "right"
					),
				}
		end
		table.insert(lines, text)
	end
	return lines, nil
end

local function validate_local_worktree_thread(session, thread)
	if not is_local_worktree_session(session) or is_remote_thread(thread) then
		return true, nil
	end
	local lines, err = target_remote_text(session, thread.target)
	if not lines then
		return nil, err
	end
	local anchor = thread.metadata and thread.metadata.anchor
	local selected = anchor and anchor.selected
	local side = thread.target and (thread.target.side or thread.target.start_side)
	if selected and side ~= "left" and #selected == #lines then
		for index, text in ipairs(selected) do
			if text ~= lines[index] then
				return nil,
					{
						message = string.format(
							"%s:%d is local-only or differs from the remote PR diff; push the change before publishing this draft",
							tostring(thread.target.path),
							thread.target.start_line or thread.target.line or 0
						),
					}
			end
		end
	end
	return true, nil
end

local function local_line_map(file, side)
	local lines = {}
	for _, hunk in ipairs((file and file.hunks) or {}) do
		for _, line in ipairs(hunk.lines or {}) do
			if side == "left" and line.kind ~= "added" and line.old_line then
				lines[line.old_line] = line.text
			elseif side ~= "left" and line.kind ~= "deleted" and line.new_line then
				lines[line.new_line] = line.text
			end
		end
	end
	return lines
end

local function mapped_lines_match(lines, start_line, selected)
	if not start_line then
		return false
	end
	for offset, text in ipairs(selected or {}) do
		if lines[start_line + offset - 1] ~= text then
			return false
		end
	end
	return true
end

local function find_local_matches(lines, selected)
	local matches = {}
	if not selected or #selected == 0 then
		return matches
	end
	for start_line in pairs(lines or {}) do
		if mapped_lines_match(lines, start_line, selected) then
			table.insert(matches, start_line)
		end
	end
	table.sort(matches)
	return matches
end

local function thread_github_outdated(thread)
	local github = thread and thread.metadata and thread.metadata.github
	return github and github.isOutdated == true
end

local function apply_local_thread_target(thread, start_line, count)
	local target = thread.target or {}
	count = count or 1
	if count == 1 and target.kind == "line" then
		target.line = start_line
	else
		target.kind = "range"
		target.start_line = start_line
		target.line = start_line + count - 1
		target.start_side = target.start_side or target.side
	end
	thread.target = target
	thread.metadata = thread.metadata or {}
	thread.metadata.local_outdated = false
	if not thread_github_outdated(thread) then
		thread.is_outdated = false
		if thread.state == "stale" then
			thread.state = "open"
		end
	end
	for _, comment in ipairs(thread.comments or {}) do
		comment.target = target
	end
end

local function mark_local_thread_stale(thread)
	thread.metadata = thread.metadata or {}
	thread.metadata.local_outdated = true
	thread.is_outdated = true
	if thread.state == "open" then
		thread.state = "stale"
	end
end

local function reconcile_remote_thread_with_local(session, thread)
	if not is_local_worktree_session(session) or not is_remote_thread(thread) then
		return
	end
	local target = thread.target
	if not target or target.kind == "file" then
		return
	end
	local selected = target_remote_text(session, target)
	if not selected or #selected == 0 then
		mark_local_thread_stale(thread)
		return
	end
	local file = find_local_file(session, target.path)
	if not file then
		mark_local_thread_stale(thread)
		return
	end
	local side = target.side or target.start_side or "right"
	local start_line = target.start_line or target.line
	local lines = local_line_map(file, side)
	if mapped_lines_match(lines, start_line, selected) then
		apply_local_thread_target(thread, start_line, #selected)
		return
	end
	local matches = find_local_matches(lines, selected)
	if #matches == 1 then
		apply_local_thread_target(thread, matches[1], #selected)
		return
	end
	mark_local_thread_stale(thread)
end

local function reconcile_remote_threads_with_local(session, threads)
	if not is_local_worktree_session(session) then
		return threads
	end
	for _, thread in ipairs(threads or {}) do
		reconcile_remote_thread_with_local(session, thread)
	end
	return threads
end

local function local_worktree_publish_error(err)
	return {
		message = (err and err.message or "draft target is not present in the remote PR diff")
			.. "; push or update the PR, refresh the review, then publish drafts",
	}
end

local function ensure_pending_review(session)
	session.metadata = session.metadata or {}
	session.metadata.github = session.metadata.github or {}
	if session.metadata.github.pending_review_id then
		return session.metadata.github.pending_review_id, nil
	end
	local review_id, err = graphql.create_pending_review(session.target, opts_for(session))
	if not review_id then
		return nil, err
	end
	session.metadata.github.pending_review_id = review_id
	pcall(session_store.write, session)
	return review_id, nil
end

local function persisted_session(session)
	if not session or not session.id or not session.target or not session.target.root then
		return nil
	end
	local ok, data = pcall(session_store.read, session.target.root, session.id)
	if not ok or not data then
		return nil
	end
	return data
end

local function persisted_export_marks(session)
	local data = persisted_session(session)
	if not data then
		return {}
	end
	local marks = {}
	for _, thread in ipairs(data.threads or {}) do
		if thread.id and thread.metadata and thread.metadata.export ~= nil then
			marks[thread.id] = thread.metadata.export == true
		end
	end
	return marks
end

local function apply_persisted_export_marks(session, threads)
	local marks = persisted_export_marks(session)
	for _, thread in ipairs(threads or {}) do
		if marks[thread.id] ~= nil then
			thread.metadata = thread.metadata or {}
			thread.metadata.export = marks[thread.id]
		end
	end
	review_thread.mark_draft_exports(threads)
end

local function comment_ids(thread)
	local ids = {}
	for _, comment in ipairs((thread and thread.comments) or {}) do
		if comment.id then
			ids[comment.id] = comment
		end
	end
	return ids
end

local function merge_persisted_drafts(session, remote_threads)
	local data = persisted_session(session)
	if not data then
		return remote_threads
	end
	local by_id = {}
	for _, thread in ipairs(remote_threads or {}) do
		if thread.id then
			by_id[thread.id] = thread
		end
	end
	for _, stored in ipairs(data.threads or {}) do
		if has_drafts(stored) then
			local remote = stored.id and by_id[stored.id]
			if remote and is_remote_thread(stored) then
				remote.metadata = remote.metadata or {}
				if stored.metadata and stored.metadata.export ~= nil then
					remote.metadata.export = stored.metadata.export
				end
				local remote_comments = comment_ids(remote)
				for _, draft in ipairs(draft_comments(stored)) do
					draft.comment.thread_id = remote.id
					draft.comment.target = remote.target
					local existing = draft.comment.id and remote_comments[draft.comment.id]
					if existing and comment_status.is_remote_draft(draft.comment) then
						existing.state = "draft"
						existing.metadata =
							vim.tbl_deep_extend("force", existing.metadata or {}, draft.comment.metadata or {})
					elseif not existing then
						table.insert(remote.comments, draft.comment)
					end
				end
			elseif not is_remote_thread(stored) or has_drafts(stored, { remote_only = true }) then
				table.insert(remote_threads, stored)
			end
		end
	end
	review_thread.mark_draft_exports(remote_threads)
	return remote_threads
end

function M.load(session)
	local threads, err = graphql.fetch_review_threads(session.target, opts_for(session))
	if not threads then
		session.threads = session.threads or {}
		return nil, err
	end
	apply_persisted_export_marks(session, threads)
	session.threads = reconcile_remote_threads_with_local(session, merge_persisted_drafts(session, threads))
	local data = persisted_session(session)
	if data and data.session and data.session.metadata then
		session.metadata = vim.tbl_deep_extend("force", session.metadata or {}, data.session.metadata)
	end
	return session.threads, nil
end

function M.list_threads(session, path)
	local threads = {}
	for _, thread in ipairs(session.threads or {}) do
		if not path or (thread.target and thread.target.path == path) then
			table.insert(threads, thread)
		end
	end
	return threads
end

function M.create_thread(session, target, body, opts)
	opts = opts or {}
	local metadata = vim.tbl_deep_extend("force", { export = true }, opts.metadata or {})
	if is_local_worktree_session(session) then
		metadata.github_local_worktree = true
		metadata.publish_note = "This draft can publish only after its target line exists in the remote PR diff."
	end
	local thread, err =
		local_store.create_thread(session, target, body, vim.tbl_extend("force", opts, { metadata = metadata }))
	if not thread then
		return nil, err
	end
	if is_local_worktree_session(session) then
		vim.notify(
			"Created a local-worktree PR draft. It can publish after the matching code is pushed to the PR.",
			vim.log.levels.INFO,
			{ title = "unified-review" }
		)
	end
	return thread, nil
end

function M.reply(session, thread_id, body)
	return local_store.reply(session, thread_id, body)
end

function M.resolve_thread(session, thread_id, state)
	local thread = find_thread(session, thread_id)
	if not is_remote_thread(thread) then
		return local_store.resolve_thread(session, thread_id, state)
	end
	if state == "resolved" then
		local _, err = graphql.resolve_thread(thread_id, opts_for(session))
		if err then
			return nil, err
		end
		thread.state = "resolved"
	else
		local _, err = graphql.unresolve_thread(thread_id, opts_for(session))
		if err then
			return nil, err
		end
		thread.state = "open"
	end
	pcall(session_store.write, session)
	return thread, nil
end

function M.unresolve_thread(session, thread_id)
	return M.resolve_thread(session, thread_id, "open")
end

local function mark_remote_draft(comment, review_id)
	comment.metadata = comment.metadata or {}
	comment.metadata.github = comment.metadata.github or {}
	comment.metadata.github_pending_review_id = review_id
	comment.state = "draft"
	return comment
end

local function replace_comment(thread, index, comment, review_id)
	comment.thread_id = thread.id
	comment.target = thread.target
	mark_remote_draft(comment, review_id)
	thread.comments[index] = comment
end

local function publish_remote_thread_replies(session, review_id, thread)
	local count = 0
	for _, draft in ipairs(draft_comments(thread, { local_only = true })) do
		local comment, err = graphql.add_reply(thread.id, draft.comment.body, opts_for(session))
		if not comment then
			return nil, err
		end
		replace_comment(thread, draft.index, comment, review_id)
		count = count + 1
		pcall(session_store.write, session)
	end
	return count, nil
end

local function publish_local_thread(session, review_id, thread_index, thread)
	local drafts = draft_comments(thread, { local_only = true })
	if #drafts == 0 then
		return 0, nil
	end
	local remote_thread, err = graphql.add_thread(review_id, thread.target, drafts[1].comment.body, opts_for(session))
	if not remote_thread then
		return nil, err
	end
	remote_thread.metadata = remote_thread.metadata or {}
	remote_thread.metadata.export = thread.metadata and thread.metadata.export
	for _, comment in ipairs(remote_thread.comments or {}) do
		comment.thread_id = remote_thread.id
		comment.target = remote_thread.target
		mark_remote_draft(comment, review_id)
	end
	for draft_index = 2, #drafts do
		local comment, reply_err =
			graphql.add_reply(remote_thread.id, drafts[draft_index].comment.body, opts_for(session))
		if not comment then
			return nil, reply_err
		end
		comment.thread_id = remote_thread.id
		comment.target = remote_thread.target
		mark_remote_draft(comment, review_id)
		table.insert(remote_thread.comments, comment)
	end
	session.threads[thread_index] = remote_thread
	pcall(session_store.write, session)
	return #drafts, nil
end

function M.publish_drafts(session)
	session.threads = session.threads or {}
	local candidates = {}
	for index, thread in ipairs(session.threads) do
		if has_local_drafts(thread) and review_thread.is_exported(thread) then
			table.insert(candidates, { index = index, thread = thread })
		end
	end
	if #candidates == 0 then
		return nil, { message = "No exported draft comments to publish" }
	end
	for _, candidate in ipairs(candidates) do
		local ok, publish_err = validate_local_worktree_thread(session, candidate.thread)
		if not ok then
			return nil, local_worktree_publish_error(publish_err)
		end
	end
	local review_id, review_err = ensure_pending_review(session)
	if not review_id then
		return nil, review_err
	end
	local published_comments = 0
	for _, candidate in ipairs(candidates) do
		local count, err
		if is_remote_thread(candidate.thread) then
			count, err = publish_remote_thread_replies(session, review_id, candidate.thread)
		else
			count, err = publish_local_thread(session, review_id, candidate.index, candidate.thread)
		end
		if not count then
			return nil, err
		end
		published_comments = published_comments + count
	end
	pcall(session_store.write, session)
	return { review_id = review_id, comments = published_comments, threads = #candidates }, nil
end

function M.submit_review(session, event, body)
	if session.kind == "github_pr" then
		local has_exported_local_drafts = false
		for _, thread in ipairs(session.threads or {}) do
			if has_local_drafts(thread) and review_thread.is_exported(thread) then
				has_exported_local_drafts = true
				break
			end
		end
		if has_exported_local_drafts then
			local _, publish_err = M.publish_drafts(session)
			if publish_err then
				return nil, publish_err
			end
		end
	end
	local review_id = session.metadata and session.metadata.github and session.metadata.github.pending_review_id
	if not review_id then
		return nil, { message = "No pending GitHub review to submit" }
	end
	local submitted, err = graphql.submit_review(review_id, event or "COMMENT", body or "", opts_for(session))
	if not submitted then
		return nil, err
	end
	session.metadata.github.pending_review_id = nil
	for _, thread in ipairs(session.threads or {}) do
		for _, comment in ipairs(thread.comments or {}) do
			if comment_status.is_remote_draft(comment) then
				comment.state = "remote"
			end
		end
	end
	pcall(session_store.write, session)
	return submitted, nil
end

local function find_comment(session, comment_id)
	for _, thread in ipairs(session.threads or {}) do
		for _, comment in ipairs(thread.comments or {}) do
			if comment.id == comment_id then
				return comment
			end
		end
	end
	return nil
end

local function github_comment_id(comment)
	local metadata = comment_status.github_metadata(comment)
	local id = metadata and metadata.id or (comment and comment.id)
	if id == vim.NIL then
		return nil
	end
	return id
end

function M.edit_draft(session, comment_id, body)
	local comment = find_comment(session, comment_id)
	if not comment then
		return nil, { message = "comment not found: " .. tostring(comment_id) }
	end
	if not comment_status.is_local_draft(comment) then
		return nil, { message = "Only local draft comments can be edited" }
	end
	return local_store.edit_draft(session, comment_id, body)
end

function M.delete_draft(session, comment_id)
	local comment = find_comment(session, comment_id)
	if not comment then
		return nil, { message = "comment not found: " .. tostring(comment_id) }
	end
	if comment_status.is_local_draft(comment) then
		return local_store.delete_draft(session, comment_id)
	end
	if comment_status.is_remote_draft(comment) then
		local remote_id = github_comment_id(comment)
		if not remote_id then
			return nil, { message = "GitHub comment id is required to delete remote draft" }
		end
		local _, err = graphql.delete_review_comment(remote_id, opts_for(session))
		if err then
			return nil, err
		end
		return local_store.delete_draft(session, comment_id)
	end
	return nil, { message = "Only draft comments can be deleted" }
end

function M.clear(session)
	local changed = false
	local kept_threads = {}
	for _, thread in ipairs(session.threads or {}) do
		local kept_comments = {}
		for _, comment in ipairs(thread.comments or {}) do
			if comment_status.is_local_draft(comment) then
				changed = true
			else
				table.insert(kept_comments, comment)
			end
		end
		if #kept_comments > 0 or not has_local_drafts(thread) then
			thread.comments = kept_comments
			table.insert(kept_threads, thread)
		end
	end
	if not changed then
		return nil, { message = "No local draft comments to clear" }
	end
	session.threads = kept_threads
	local ok, err = pcall(session_store.write, session)
	if not ok then
		return nil, { message = tostring(err) }
	end
	return true, nil
end

function M.undo(session)
	return local_store.undo(session)
end

return M
