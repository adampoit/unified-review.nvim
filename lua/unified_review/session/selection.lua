local M = {}

function M.initialize(session)
	session.selection = session.selection or {}
	session.selection.file_index = session.selection.file_index or (#session.files > 0 and 1 or nil)
	session.selection.hunk_index = session.selection.hunk_index or 1
	return session.selection
end

function M.current_file(session)
	if not session or not session.selection or not session.selection.file_index then
		return nil
	end
	return session.files[session.selection.file_index]
end

function M.select_file(session, index)
	if index < 1 or index > #session.files then
		return nil
	end
	session.selection.file_index = index
	session.selection.hunk_index = 1
	return M.current_file(session)
end

function M.next_file(session)
	return M.select_file(session, math.min((session.selection.file_index or 0) + 1, #session.files))
end

function M.previous_file(session)
	return M.select_file(session, math.max((session.selection.file_index or 1) - 1, 1))
end

function M.current_hunk(session)
	local file = M.current_file(session)
	if not file then
		return nil
	end
	return file.hunks[session.selection.hunk_index]
end

local function side_for_file(file, side)
	if file and file.status == "added" then
		return "right"
	end
	if file and file.status == "deleted" then
		return "left"
	end
	return side or "right"
end

function M.row_for_target(session, target, side)
	local file = M.current_file(session)
	if not file or not target or target.path ~= file.path then
		return nil
	end
	if target.kind == "file" then
		return 1
	end
	side = side_for_file(file, side)
	if target.side and target.side ~= side then
		return nil
	end
	-- With real file content, buffer row equals line number.
	if target.line then
		return target.line
	end
	return target.start_line or 1
end

function M.target_for_row(session, row, side)
	local file = M.current_file(session)
	if not file then
		return nil
	end
	side = side_for_file(file, side)
	-- With real file content, the buffer row is the file line number.
	if row and row > 0 then
		return { kind = "line", path = file.path, side = side, line = row }
	end
	return { kind = "file", path = file.path }
end

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function current_side(session, win)
	local ui = session and session.ui or {}
	local buf = vim.api.nvim_get_current_buf()
	if ui.right_buffer and buf == ui.right_buffer then
		return "right"
	end
	if ui.left_buffer and buf == ui.left_buffer then
		return "left"
	end
	if win == ui.right_window then
		return "right"
	end
	if win == ui.left_window then
		return "left"
	end
	return "right"
end

local function normalize_path(path, root)
	if not path then
		return nil
	end
	path = tostring(path):gsub("\\", "/"):gsub("^%./", "")
	if path:match("^/") and root and root ~= "" then
		local real_root = vim.loop.fs_realpath(root) or vim.fn.fnamemodify(root, ":p")
		local real_path = vim.loop.fs_realpath(path) or vim.fn.fnamemodify(path, ":p")
		real_root = tostring(real_root):gsub("\\", "/"):gsub("/$", "")
		real_path = tostring(real_path):gsub("\\", "/")
		local prefix = real_root .. "/"
		if real_path:sub(1, #prefix) == prefix then
			return real_path:sub(#prefix + 1)
		end
	end
	return path
end

local function select_file_by_path(session, path)
	local root = session and session.target and session.target.root
	path = normalize_path(path, root)
	if not path then
		return nil
	end
	for index, file in ipairs(session.files or {}) do
		if normalize_path(file.path, root) == path or normalize_path(file.old_path, root) == path then
			session.selection = session.selection or {}
			session.selection.file_index = index
			return file
		end
	end
	return nil
end

local function select_codediff_file_for_side(session, side)
	local ui = session and session.ui or {}
	if not ui.codediff_tab then
		return nil
	end
	local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
	if not ok or type(lifecycle.get_paths) ~= "function" then
		return nil
	end
	local original_path, modified_path = lifecycle.get_paths(ui.codediff_tab)
	local path = side == "left" and original_path or modified_path
	if not path or path == "" then
		path = side == "left" and modified_path or original_path
	end
	return select_file_by_path(session, path)
end

local function codediff_explorer_target(session)
	local ui = session and session.ui or {}
	local codediff_session = ui.codediff_session
	if not codediff_session and ui.codediff_tab then
		local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
		if ok then
			codediff_session = lifecycle.get_session(ui.codediff_tab)
		end
	end
	local explorer = codediff_session and codediff_session.explorer
	if not (explorer and explorer.bufnr and vim.api.nvim_get_current_buf() == explorer.bufnr) then
		return nil
	end
	local node = explorer.tree and explorer.tree.get_node and explorer.tree:get_node()
	local data = node and node.data or {}
	if data.type == "group" or data.type == "directory" then
		return nil
	end
	local path = normalize_path(data.path or explorer.current_file_path)
	if not path then
		return nil
	end
	select_file_by_path(session, path)
	return { kind = "file", path = path }
end

function M.target_for_range(session, start_row, end_row, side)
	start_row = tonumber(start_row)
	end_row = tonumber(end_row)
	if not start_row or not end_row or start_row < 1 or end_row < 1 then
		return nil
	end
	if start_row > end_row then
		start_row, end_row = end_row, start_row
	end
	local start_target = M.target_for_row(session, start_row, side)
	local end_target = M.target_for_row(session, end_row, side)
	if not start_target or not end_target or start_target.kind == "file" or end_target.kind == "file" then
		return start_target or end_target
	end
	if start_target.line == end_target.line then
		return end_target
	end
	return {
		kind = "range",
		path = end_target.path,
		start_side = start_target.side,
		start_line = start_target.line,
		side = end_target.side,
		line = end_target.line,
	}
end

function M.visual_target(session, side)
	local vstart = vim.fn.getpos("v")
	local vend = vim.fn.getpos(".")
	local target = M.target_for_range(session, vstart[2], vend[2], side)
	if target then
		return target
	end
	vstart = vim.fn.getpos("'<")
	vend = vim.fn.getpos("'>")
	return M.target_for_range(session, vstart[2], vend[2], side)
end

function M.current_target(session)
	if not session or not session.ui then
		return nil
	end
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	if
		win ~= session.ui.left_window
		and win ~= session.ui.right_window
		and buf ~= session.ui.left_buffer
		and buf ~= session.ui.right_buffer
	then
		return nil
	end
	local side = current_side(session, win)
	select_codediff_file_for_side(session, side)
	local mode = vim.fn.mode()
	if mode:match("^[vV]") or mode == "\022" then
		return M.visual_target(session, side)
	end
	local row = vim.api.nvim_win_get_cursor(win)[1]
	return M.target_for_row(session, row, side)
end

function M.ensure_comment_target(session)
	if not session then
		return nil
	end
	local ui = session.ui or {}
	local explorer_target = codediff_explorer_target(session)
	if explorer_target then
		return explorer_target
	end
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	if (win == ui.right_window and valid_win(ui.right_window)) or buf == ui.right_buffer then
		select_codediff_file_for_side(session, "right")
		local row = vim.api.nvim_win_get_cursor(win)[1]
		return M.target_for_row(session, row, "right")
	end
	if (win == ui.left_window and valid_win(ui.left_window)) or buf == ui.left_buffer then
		select_codediff_file_for_side(session, "left")
		local row = vim.api.nvim_win_get_cursor(win)[1]
		return M.target_for_row(session, row, "left")
	end
	if valid_win(ui.right_window) then
		vim.api.nvim_set_current_win(ui.right_window)
		select_codediff_file_for_side(session, "right")
		local row = vim.api.nvim_win_get_cursor(ui.right_window)[1]
		return M.target_for_row(session, row, "right")
	end
	local file = M.current_file(session)
	if file then
		return { kind = "file", path = file.path }
	end
	return nil
end

function M.next_hunk(session)
	local file = M.current_file(session)
	if not file then
		return nil
	end
	session.selection.hunk_index = math.min((session.selection.hunk_index or 0) + 1, #file.hunks)
	return M.current_hunk(session)
end

function M.previous_hunk(session)
	local file = M.current_file(session)
	if not file then
		return nil
	end
	session.selection.hunk_index = math.max((session.selection.hunk_index or 1) - 1, 1)
	return M.current_hunk(session)
end

function M.current_threads(session)
	local file = M.current_file(session)
	if not file then
		return {}
	end
	local threads = {}
	for _, thread in ipairs(session.threads or {}) do
		if thread.target and thread.target.path == file.path then
			table.insert(threads, thread)
		end
	end
	return threads
end

function M.threads_at_target(session, target)
	local found = {}
	if not target then
		return found
	end
	for _, thread in ipairs(session.threads or {}) do
		local thread_target = thread.target or {}
		if thread_target.path == target.path then
			if thread_target.kind == "file" or target.kind == "file" then
				table.insert(found, thread)
			else
				local start_line = thread_target.start_line or thread_target.line
				local end_line = thread_target.line or thread_target.start_line
				local line = target.line or target.start_line
				if
					line
					and start_line
					and end_line
					and line >= math.min(start_line, end_line)
					and line <= math.max(start_line, end_line)
				then
					table.insert(found, thread)
				end
			end
		end
	end
	return found
end

--- All threads overlapping the cursor target in the active diff buffer. When
--- several threads overlap (e.g. a multiline range comment and a single-line
--- comment on a line inside that range), callers should disambiguate rather
--- than silently picking one. Callers wanting the `]t`/`[t`-navigated thread
--- should use `current_threads(session)[session.selection.thread_index or 1]`.
function M.current_thread_candidates(session)
	if not session or not session.ui then
		return {}
	end
	local target = M.current_target(session)
	if not target then
		return {}
	end
	return M.threads_at_target(session, target)
end

function M.select_thread(session, index)
	local threads = M.current_threads(session)
	if #threads == 0 then
		session.selection.thread_index = nil
		return nil
	end
	session.selection.thread_index = math.max(1, math.min(index, #threads))
	return threads[session.selection.thread_index]
end

function M.next_thread(session)
	return M.select_thread(session, (session.selection.thread_index or 0) + 1)
end

function M.previous_thread(session)
	return M.select_thread(session, (session.selection.thread_index or 1) - 1)
end

return M
