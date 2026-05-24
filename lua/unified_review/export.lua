local review_thread = require("unified_review.domain.review_thread")

local M = {}

local function export_threads(threads, opts)
	opts = opts or {}
	if opts.include_unmarked or opts.marked_only == false then
		return threads or {}
	end
	local exported = {}
	for _, thread in ipairs(threads or {}) do
		if review_thread.is_exported(thread) then
			table.insert(exported, thread)
		end
	end
	return exported
end

local function sorted_threads(threads, opts)
	local copy = vim.deepcopy(export_threads(threads, opts))
	table.sort(copy, function(left, right)
		local lt = left.target or {}
		local rt = right.target or {}
		if (lt.path or "") ~= (rt.path or "") then
			return (lt.path or "") < (rt.path or "")
		end
		return (lt.line or lt.start_line or 0) < (rt.line or rt.start_line or 0)
	end)
	return copy
end

local function target_line(target)
	if not target then
		return "unknown"
	end
	if target.kind == "file" then
		return target.path
	end
	if target.kind == "line" then
		return string.format("%s:L%s", target.path, target.line)
	end
	return string.format("%s:L%s-L%s", target.path, target.start_line, target.line)
end

local function append_body(lines, body)
	body = body or ""
	if body == "" then
		table.insert(lines, "")
		return
	end
	for _, line in ipairs(vim.split(body, "\n", { plain = true })) do
		table.insert(lines, line)
	end
end

function M.format_minimal(threads, opts)
	local lines = {}
	for _, thread in ipairs(sorted_threads(threads, opts)) do
		for _, comment in ipairs(thread.comments or {}) do
			local first_line = (comment.body or ""):match("([^\n]*)") or ""
			table.insert(lines, string.format("%s: %s", target_line(thread.target or comment.target), first_line))
		end
	end
	if #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n")
end

function M.format_markdown(threads, opts)
	opts = opts or {}
	local sorted = sorted_threads(threads, opts)
	if #sorted == 0 then
		return ""
	end
	local lines = {
		"# Code Review",
		"",
		string.format("**Total Threads**: %d", #sorted),
		"",
	}
	if opts.session and opts.session.target then
		local t = opts.session.target
		table.insert(lines, string.format("**Target**: %s", t.root or t.repo_root or t.kind or "local"))
		table.insert(lines, "")
	end
	local current_path
	for _, thread in ipairs(sorted) do
		local thread_target = thread.target or {}
		if thread_target.path ~= current_path then
			current_path = thread_target.path
			table.insert(lines, string.format("## %s", current_path or "unknown"))
			table.insert(lines, "")
		end
		table.insert(lines, string.format("### %s", target_line(thread_target)))
		table.insert(lines, "")
		table.insert(lines, string.format("**Status**: `%s`", thread.state or "open"))
		table.insert(lines, "")
		for _, comment in ipairs(thread.comments or {}) do
			table.insert(
				lines,
				string.format(
					"**%s**%s",
					comment.author or "local",
					comment.created_at and (" (" .. comment.created_at .. ")") or ""
				)
			)
			table.insert(lines, "")
			append_body(lines, comment.body)
			table.insert(lines, "")
		end
	end
	return table.concat(lines, "\n")
end

function M.format(threads, opts)
	opts = opts or {}
	if opts.format == "minimal" then
		return M.format_minimal(threads, opts)
	end
	return M.format_markdown(threads, opts)
end

function M.copy(threads, opts)
	local text = M.format(threads, opts)
	vim.fn.setreg(opts and opts.register or "+", text)
	return text
end

function M.save(path, threads, opts)
	path = assert(path, "path is required")
	local text = M.format(threads, opts)
	vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
	return text
end

M.target_line = target_line

return M
