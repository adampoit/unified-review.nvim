local comment_status = require("unified_review.domain.comment_status")
local target = require("unified_review.domain.comment_target")
local review_thread = require("unified_review.domain.review_thread")
local selection = require("unified_review.session.selection")

local M = {}

M.STATE_ICONS = {
	open = "●",
	resolved = "✓",
	stale = "⚠",
	draft = "✎",
	action_required = "●",
	waiting_review = "◐",
}

M.FILTER_STATES = { "open", "resolved", "draft", "stale" }
M.EXPORT_ICON = "⇪"

function M.export_icon(thread)
	return review_thread.is_exported(thread) and M.EXPORT_ICON or " "
end

function M.thread_state(thread)
	local state = thread and thread.state or "open"
	if thread and (thread.is_outdated or state == "stale") then
		return "stale"
	end
	if state == "resolved" then
		return "resolved"
	end
	for _, comment in ipairs((thread and thread.comments) or {}) do
		if comment_status.is_draft(comment) then
			return "draft"
		end
	end
	if M.STATE_ICONS[state] then
		return state
	end
	return "open"
end

function M.thread_state_label(thread)
	if M.thread_state(thread) ~= "draft" then
		return M.thread_state(thread)
	end
	for _, comment in ipairs((thread and thread.comments) or {}) do
		if comment_status.is_local_draft(comment) then
			return "local draft"
		end
	end
	for _, comment in ipairs((thread and thread.comments) or {}) do
		if comment_status.is_remote_draft(comment) then
			return "remote draft"
		end
	end
	return "draft"
end

function M.preview_text(comment)
	if not comment or not comment.body then
		return ""
	end
	local body = tostring(comment.body)
	if body:match("^%s*```suggestion") then
		return "[suggestion block]"
	end
	for line in body:gmatch("([^\n]*)\n?") do
		local text = line:gsub("^%s+", ""):gsub("%s+$", "")
		if text ~= "" and not text:match("^```") then
			return text
		end
	end
	return ""
end

function M.truncate(text, width)
	text = text or ""
	if #text > width then
		return text:sub(1, math.max(width - 3, 1)) .. "..."
	end
	return text
end

function M.target_label(th_target)
	th_target = th_target or {}
	if th_target.kind == "file" then
		return "File"
	end
	local is_range = th_target.kind == "range"
		or (th_target.start_line and th_target.line and th_target.start_line ~= th_target.line)
	if is_range then
		return string.format(
			"L%d-L%d",
			th_target.start_line or th_target.line or 0,
			th_target.line or th_target.start_line or 0
		)
	end
	return string.format("L%d", th_target.line or th_target.start_line or 0)
end

function M.filter_for(session)
	session._thread_filter = session._thread_filter or { open = true, resolved = true, draft = true, stale = true }
	for _, state_name in ipairs(M.FILTER_STATES) do
		if session._thread_filter[state_name] == nil then
			session._thread_filter[state_name] = true
		end
	end
	return session._thread_filter
end

function M.scope_for(session)
	local scope = session and session._thread_scope or nil
	if scope == "current" then
		return "current"
	end
	return "project"
end

function M.thread_search_text(thread)
	local parts = { thread.id or "", M.thread_state(thread) }
	local th_target = thread.target or {}
	table.insert(parts, th_target.path or "")
	table.insert(parts, target.label and target.label(th_target) or "")
	for _, comment in ipairs(thread.comments or {}) do
		table.insert(parts, comment.author or "")
		table.insert(parts, comment.body or "")
	end
	return table.concat(parts, "\n"):lower()
end

local function query_tokens(query)
	query = query and vim.trim(query) or ""
	local tokens = {}
	for token in query:lower():gmatch("%S+") do
		table.insert(tokens, token)
	end
	return tokens
end

local function matches_query(thread, query)
	local tokens = query_tokens(query)
	if #tokens == 0 then
		return true
	end
	local haystack = M.thread_search_text(thread)
	for _, token in ipairs(tokens) do
		if not haystack:find(token, 1, true) then
			return false
		end
	end
	return true
end

local function target_line_number(thread)
	local th_target = thread.target or {}
	if th_target.kind == "file" then
		return 0
	end
	local line = th_target.start_line or th_target.line
	if type(line) == "number" then
		return line
	end
	return tonumber(line) or 0
end

local function file_order(session)
	local order = {}
	for index, file in ipairs((session and session.files) or {}) do
		if file.path then
			order[file.path] = index
		end
	end
	return order
end

local function sort_threads(session, threads)
	local order = file_order(session)
	table.sort(threads, function(a, b)
		local at = a.target or {}
		local bt = b.target or {}
		local ap = at.path or ""
		local bp = bt.path or ""
		local ao = order[ap] or math.huge
		local bo = order[bp] or math.huge
		if ao ~= bo then
			return ao < bo
		end
		if ap ~= bp then
			return ap < bp
		end
		local aline = target_line_number(a)
		local bline = target_line_number(b)
		if aline ~= bline then
			return aline < bline
		end
		return tostring(a.id or "") < tostring(b.id or "")
	end)
end

function M.filtered_threads(session, opts)
	opts = opts or {}
	if not session then
		return {}
	end
	local include = opts.filter or M.filter_for(session)
	local query = opts.ignore_query and nil or (opts.query ~= nil and opts.query or session._thread_query)
	local scope = opts.scope or M.scope_for(session)
	local current_file = selection.current_file(session)
	local candidates = {}
	for _, thread in ipairs(session.threads or {}) do
		local th_target = thread.target or {}
		if scope ~= "current" or (current_file and th_target.path == current_file.path) then
			local st = M.thread_state(thread)
			if include[st] and matches_query(thread, query) then
				table.insert(candidates, thread)
			end
		end
	end
	sort_threads(session, candidates)
	return candidates
end

function M.group_by_file(session, threads)
	threads = vim.deepcopy(threads or M.filtered_threads(session))
	local order = file_order(session or {})
	table.sort(threads, function(a, b)
		local ap = (a.target or {}).path or ""
		local bp = (b.target or {}).path or ""
		local ao = order[ap] or math.huge
		local bo = order[bp] or math.huge
		if ao ~= bo then
			return ao < bo
		end
		if ap ~= bp then
			return ap < bp
		end
		local aline = target_line_number(a)
		local bline = target_line_number(b)
		if aline ~= bline then
			return aline < bline
		end
		return tostring(a.id or "") < tostring(b.id or "")
	end)

	local groups = {}
	local by_path = {}
	for _, thread in ipairs(threads) do
		local path = (thread.target or {}).path or "unknown"
		local group = by_path[path]
		if not group then
			group = { path = path, threads = {} }
			by_path[path] = group
			table.insert(groups, group)
		end
		table.insert(group.threads, thread)
	end
	return groups
end

function M.summary(session)
	local result = {
		files = #(session and session.files or {}),
		files_with_threads = 0,
		threads = #(session and session.threads or {}),
		open = 0,
		resolved = 0,
		draft = 0,
		local_draft = 0,
		remote_draft = 0,
		stale = 0,
	}
	local paths = {}
	for _, thread in ipairs((session and session.threads) or {}) do
		local st = M.thread_state(thread)
		if result[st] ~= nil then
			result[st] = result[st] + 1
		elseif st ~= "resolved" then
			result.open = result.open + 1
		end
		if st == "draft" then
			local label = M.thread_state_label(thread)
			if label == "local draft" then
				result.local_draft = result.local_draft + 1
			elseif label == "remote draft" then
				result.remote_draft = result.remote_draft + 1
			end
		end
		local path = thread.target and thread.target.path
		if path and not paths[path] then
			paths[path] = true
			result.files_with_threads = result.files_with_threads + 1
		end
	end
	return result
end

return M
