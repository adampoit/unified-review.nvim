local diff_view = require("unified_review.ui.diff_view")
local selection = require("unified_review.session.selection")
local state = require("unified_review.session.state")

local M = {}

local function active_session()
	local session = state.get_active()
	if not session then
		vim.notify("No active review session", vim.log.levels.INFO, { title = "unified-review" })
	end
	return session
end

local function rerender(session)
	diff_view.render(session)
end

local function mark_viewed(session)
	if session.viewed_files and session.current_file then
		session.viewed_files[session.current_file] = true
	end
end

function M.next_file()
	local session = active_session()
	if not session then
		return nil
	end
	local ok, codediff = pcall(require, "codediff")
	if ok and session.ui and session.ui.codediff_tab then
		codediff.next_file()
		mark_viewed(session)
		pcall(require("unified_review.integrations.codediff_explorer").refresh, session.ui.codediff_tab)
		return selection.current_file(session)
	end
	local file = selection.next_file(session)
	rerender(session)
	return file
end

function M.previous_file()
	local session = active_session()
	if not session then
		return nil
	end
	local ok, codediff = pcall(require, "codediff")
	if ok and session.ui and session.ui.codediff_tab then
		codediff.prev_file()
		mark_viewed(session)
		pcall(require("unified_review.integrations.codediff_explorer").refresh, session.ui.codediff_tab)
		return selection.current_file(session)
	end
	local file = selection.previous_file(session)
	rerender(session)
	return file
end

function M.next_hunk()
	local session = active_session()
	if not session then
		return nil
	end
	local hunk = selection.next_hunk(session)
	diff_view.focus_hunk(session)
	return hunk
end

local function focus_thread(session, thread)
	if not thread then
		vim.notify("No threads for current file", vim.log.levels.INFO, { title = "unified-review" })
		return
	end
	local side = thread.target.side or "right"
	local row = selection.row_for_target(session, thread.target, side) or 1
	local win = side == "left" and session.ui.left_window or session.ui.right_window
	if win and vim.api.nvim_win_is_valid(win) then
		local buf = vim.api.nvim_win_get_buf(win)
		local line_count = math.max(vim.api.nvim_buf_line_count(buf), 1)
		vim.api.nvim_set_current_win(win)
		vim.api.nvim_win_set_cursor(win, { math.min(row, line_count), 0 })
	end
end

function M.previous_hunk()
	local session = active_session()
	if not session then
		return nil
	end
	local hunk = selection.previous_hunk(session)
	diff_view.focus_hunk(session)
	return hunk
end

function M.next_thread()
	local session = active_session()
	if not session then
		return nil
	end
	local thread = selection.next_thread(session)
	focus_thread(session, thread)
	return thread
end

function M.previous_thread()
	local session = active_session()
	if not session then
		return nil
	end
	local thread = selection.previous_thread(session)
	focus_thread(session, thread)
	return thread
end

return M
