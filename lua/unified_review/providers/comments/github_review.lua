local comment_status = require("unified_review.domain.comment_status")
local graphql = require("unified_review.integrations.github_graphql")
local local_store = require("unified_review.providers.comments.local_store")
local review_thread = require("unified_review.domain.review_thread")
local session_store = require("unified_review.persist.session_store")

local M = {}

local function opts_for(session)
	local github_cfg = require("unified_review.config").options.github or {}
	return {
		cwd = session and session.target and session.target.root,
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
	session.threads = merge_persisted_drafts(session, threads)
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

function M.create_thread(session, target, body)
	local thread, err = local_store.create_thread(session, target, body, { metadata = { export = true } })
	if not thread then
		return nil, err
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
