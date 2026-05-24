local review_comment = require("unified_review.domain.review_comment")
local review_thread = require("unified_review.domain.review_thread")
local session_store = require("unified_review.persist.session_store")

local M = {}
local persist

local function snapshot_threads(session)
	return vim.deepcopy(session.threads or {})
end

local function push_undo(session, label)
	session._comment_undo = session._comment_undo or {}
	table.insert(session._comment_undo, { label = label or "comment change", threads = snapshot_threads(session) })
	if #session._comment_undo > 50 then
		table.remove(session._comment_undo, 1)
	end
end

local function restore_threads(session, threads)
	session.threads = vim.deepcopy(threads or {})
	local _, err = persist(session)
	return not err, err
end

local function file_lines(session, path)
	local root = session.target and session.target.root
	if not root or not path then
		return nil
	end
	local full_path = root .. "/" .. path
	if vim.fn.filereadable(full_path) == 0 then
		return nil
	end
	return vim.fn.readfile(full_path)
end

local function file_content_id(lines)
	if not lines then
		return nil
	end
	return vim.fn.sha256(table.concat(lines, "\n"))
end

local function target_bounds(target)
	local start_line = target and (target.start_line or target.line)
	local end_line = target and (target.line or target.start_line)
	if not start_line or not end_line then
		return nil, nil
	end
	return math.min(start_line, end_line), math.max(start_line, end_line)
end

local function target_excerpt(session, target)
	if not target or target.kind == "file" then
		return nil
	end
	local lines = file_lines(session, target.path)
	if not lines then
		return nil
	end
	local start_line, end_line = target_bounds(target)
	local selected = {}
	for line = start_line, end_line do
		table.insert(selected, lines[line] or "")
	end
	return selected
end

local function find_file(session, path)
	for _, file in ipairs(session.files or {}) do
		if file.path == path or file.old_path == path then
			return file
		end
	end
	return nil
end

local function find_hunk(file, target)
	local line = target and (target.line or target.start_line)
	local side = target and (target.side or target.start_side)
	if not file or not line or not side then
		return nil
	end
	for _, hunk in ipairs(file.hunks or {}) do
		local start_line = side == "left" and hunk.old_start or hunk.new_start
		local count = side == "left" and hunk.old_count or hunk.new_count
		if start_line and count and line >= start_line and line <= start_line + math.max(count - 1, 0) then
			return hunk
		end
	end
	return nil
end

local function context(lines, start_line, end_line, radius)
	radius = radius or 3
	local before = {}
	for line = math.max(1, start_line - radius), start_line - 1 do
		table.insert(before, lines[line] or "")
	end
	local after = {}
	for line = end_line + 1, math.min(#lines, end_line + radius) do
		table.insert(after, lines[line] or "")
	end
	return before, after
end

local function attach_anchor(session, thread)
	thread.metadata = thread.metadata or {}
	if thread.metadata.anchor or not thread.target then
		return
	end
	local target = thread.target
	local lines = file_lines(session, target.path)
	local selected = target_excerpt(session, target)
	if selected and #selected > 0 and lines then
		local start_line, end_line = target_bounds(target)
		local before, after = context(lines, start_line, end_line)
		local hunk = find_hunk(find_file(session, target.path), target)
		local anchor = require("unified_review.util.anchors").content_anchor({
			hunk_header = hunk and hunk.header,
			before = before,
			selected = selected,
			after = after,
			base_id = session.target and session.target.base_oid,
			head_id = session.target and session.target.head_oid,
		})
		anchor.file_content_id = file_content_id(lines)
		anchor.original_start_line = start_line
		anchor.original_end_line = end_line
		anchor.side = target.side or target.start_side
		thread.metadata.anchor = anchor
	end
end

local function lines_match(lines, start_line, selected)
	if start_line < 1 or start_line + #selected - 1 > #lines then
		return false
	end
	for offset = 1, #selected do
		if lines[start_line + offset - 1] ~= selected[offset] then
			return false
		end
	end
	return true
end

local function find_exact_matches(lines, selected)
	local matches = {}
	for start_line = 1, #lines - #selected + 1 do
		if lines_match(lines, start_line, selected) then
			table.insert(matches, start_line)
		end
	end
	return matches
end

local function context_score(lines, start_line, selected_count, anchor)
	local score = 0
	local before = anchor.before or {}
	for index, text in ipairs(before) do
		local line = start_line - #before + index - 1
		if line >= 1 and lines[line] == text then
			score = score + 1
		end
	end
	for index, text in ipairs(anchor.after or {}) do
		local line = start_line + selected_count + index - 1
		if line <= #lines and lines[line] == text then
			score = score + 1
		end
	end
	return score
end

local function best_context_match(lines, selected_count, anchor)
	local best_line, best_score, tied = nil, -1, false
	for start_line = 1, math.max(1, #lines - selected_count + 1) do
		local score = context_score(lines, start_line, selected_count, anchor)
		if score > best_score then
			best_line, best_score, tied = start_line, score, false
		elseif score == best_score then
			tied = true
		end
	end
	if tied or best_score < 2 then
		return nil
	end
	return best_line
end

local function hunk_header_match(session, target, anchor)
	if not anchor.hunk_header then
		return nil
	end
	local side = anchor.side or target.side or target.start_side or "right"
	for _, hunk in ipairs((find_file(session, target.path) or {}).hunks or {}) do
		if hunk.header == anchor.hunk_header then
			local original = anchor.original_start_line or target.start_line or target.line
			local hunk_start = side == "left" and hunk.old_start or hunk.new_start
			local old_hunk_start = side == "left" and hunk.old_start or hunk.new_start
			if hunk_start and old_hunk_start and original then
				return math.max(1, hunk_start + (original - old_hunk_start))
			end
			return hunk_start
		end
	end
	return nil
end

local function apply_target_line(thread, start_line, count)
	local target = thread.target
	count = count or 1
	if count == 1 and target.kind == "line" then
		target.line = start_line
	else
		target.kind = "range"
		target.start_line = start_line
		target.line = start_line + count - 1
		target.start_side = target.start_side or target.side
	end
	thread.is_outdated = false
	if thread.state == "stale" then
		thread.state = "open"
	end
	for _, comment in ipairs(thread.comments or {}) do
		comment.target = target
	end
end

local function mark_stale(thread)
	thread.is_outdated = true
	thread.state = thread.state == "open" and "stale" or thread.state
end

local function remap_with_anchor(session, thread)
	local anchor = thread.metadata and thread.metadata.anchor
	local target = thread.target
	if not anchor or not target or target.kind == "file" or not anchor.selected or #anchor.selected == 0 then
		return
	end
	local lines = file_lines(session, target.path)
	if not lines then
		mark_stale(thread)
		return
	end
	local selected = anchor.selected
	local current_start = target_bounds(target)
	local current_file_content_id = file_content_id(lines)
	if
		current_start
		and anchor.file_content_id
		and anchor.file_content_id == current_file_content_id
		and lines_match(lines, current_start, selected)
	then
		thread.is_outdated = false
		return
	end
	local exact = find_exact_matches(lines, selected)
	if #exact == 1 then
		apply_target_line(thread, exact[1], #selected)
		return
	elseif #exact > 1 then
		local best_line, best_score, tied = nil, -1, false
		for _, start_line in ipairs(exact) do
			local score = context_score(lines, start_line, #selected, anchor)
			if score > best_score then
				best_line, best_score, tied = start_line, score, false
			elseif score == best_score then
				tied = true
			end
		end
		if not tied and best_score > 0 then
			apply_target_line(thread, best_line, #selected)
			return
		end
	end
	local contextual = best_context_match(lines, #selected, anchor)
	if contextual then
		apply_target_line(thread, contextual, #selected)
		return
	end
	local hunk_line = hunk_header_match(session, target, anchor)
	if hunk_line then
		apply_target_line(thread, hunk_line, #selected)
		return
	end
	mark_stale(thread)
end

persist = function(session)
	local ok, result = pcall(session_store.write, session)
	if not ok then
		return nil, { message = result }
	end
	return result, nil
end

function M.load(session)
	local restored = session_store.restore(session)
	if restored then
		review_thread.mark_draft_exports(session.threads)
		for _, thread in ipairs(session.threads or {}) do
			remap_with_anchor(session, thread)
		end
		return session.threads or {}, nil
	end
	session.threads = session.threads or {}
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
	session.threads = session.threads or {}
	push_undo(session, "create comment")
	local metadata = vim.deepcopy(opts.metadata or {})
	if metadata.export == nil then
		metadata.export = true
	end
	local thread = review_thread.new({ target = target, state = opts.state or "open", metadata = metadata })
	attach_anchor(session, thread)
	local comment = review_comment.new({ thread_id = thread.id, target = target, body = body, author = opts.author })
	thread.comments = { comment }
	table.insert(session.threads, thread)
	local _, err = persist(session)
	if err then
		return nil, err
	end
	return thread, nil
end

function M.reply(session, thread_id, body, opts)
	opts = opts or {}
	for _, thread in ipairs(session.threads or {}) do
		if thread.id == thread_id then
			push_undo(session, "reply")
			local comment =
				review_comment.new({ thread_id = thread_id, target = thread.target, body = body, author = opts.author })
			thread.metadata = thread.metadata or {}
			if thread.metadata.export == nil then
				thread.metadata.export = true
			end
			table.insert(thread.comments, comment)
			local _, err = persist(session)
			if err then
				return nil, err
			end
			return comment, nil
		end
	end
	return nil, { message = "thread not found: " .. tostring(thread_id) }
end

function M.resolve_thread(session, thread_id, state)
	for _, thread in ipairs(session.threads or {}) do
		if thread.id == thread_id then
			push_undo(session, "update thread")
			thread.state = state or "resolved"
			persist(session)
			return thread, nil
		end
	end
	return nil, { message = "thread not found: " .. tostring(thread_id) }
end

function M.unresolve_thread(session, thread_id)
	return M.resolve_thread(session, thread_id, "open")
end

function M.edit_draft(session, comment_id, body)
	for _, thread in ipairs(session.threads or {}) do
		for _, comment in ipairs(thread.comments or {}) do
			if comment.id == comment_id then
				push_undo(session, "edit draft")
				comment.body = body
				comment.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
				persist(session)
				return comment, nil
			end
		end
	end
	return nil, { message = "comment not found: " .. tostring(comment_id) }
end

function M.clear(session)
	push_undo(session, "clear comments")
	session.threads = {}
	local _, err = persist(session)
	if err then
		return nil, err
	end
	return true, nil
end

function M.delete_draft(session, comment_id)
	for _, thread in ipairs(session.threads or {}) do
		for i, comment in ipairs(thread.comments or {}) do
			if comment.id == comment_id then
				push_undo(session, "delete draft")
				table.remove(thread.comments, i)
				if #thread.comments == 0 then
					for j, t in ipairs(session.threads) do
						if t.id == thread.id then
							table.remove(session.threads, j)
							break
						end
					end
				end
				persist(session)
				return true, nil
			end
		end
	end
	return nil, { message = "comment not found: " .. tostring(comment_id) }
end

function M.undo(session)
	local stack = session and session._comment_undo
	local entry = stack and table.remove(stack)
	if not entry then
		return nil, { message = "No comment changes to undo" }
	end
	local ok, err = restore_threads(session, entry.threads)
	if not ok then
		return nil, err
	end
	return entry.label, nil
end

return M
