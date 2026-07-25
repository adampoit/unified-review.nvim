local comment_target = require("unified_review.domain.comment_target")
local inline = require("unified_review.ui.inline")
local manager = require("unified_review.session.manager")

local M = {}

local function body_lines(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	while #lines > 0 and lines[1] == "" do
		table.remove(lines, 1)
	end
	while #lines > 0 and lines[#lines] == "" do
		table.remove(lines, #lines)
	end
	return lines
end

local function thread_for(session, thread_id)
	for _, thread in ipairs((session and session.threads) or {}) do
		if thread.id == thread_id then
			return thread
		end
	end
	return nil
end

local function target_window(session, target)
	local side = target.side or target.start_side or "right"
	local ui = session.ui or {}
	local buf = side == "left" and ui.left_buffer or ui.right_buffer
	local win = side == "left" and ui.left_window or ui.right_window
	if win and vim.api.nvim_win_is_valid(win) then
		buf = vim.api.nvim_win_get_buf(win)
		if side == "left" then
			ui.left_buffer = buf
		else
			ui.right_buffer = buf
		end
		return win, buf
	end
	for _, candidate in ipairs((buf and vim.fn.win_findbuf(buf)) or {}) do
		if vim.api.nvim_win_is_valid(candidate) then
			return candidate, buf
		end
	end
	return nil, buf
end

local function display_width(value)
	return vim.fn.strdisplaywidth(value or "")
end

local function truncate(value, width)
	value = tostring(value or "")
	if display_width(value) <= width then
		return value
	end
	if width <= 1 then
		return "…"
	end
	local out = ""
	for index = 0, vim.fn.strchars(value) - 1 do
		local char = vim.fn.strcharpart(value, index, 1)
		if display_width(out .. char .. "…") > width then
			break
		end
		out = out .. char
	end
	return out .. "…"
end

local function editor_body_height(buf, width)
	local rows = 0
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		rows = rows + math.max(1, math.ceil(display_width(line) / math.max(1, width)))
	end
	local max_height = math.max(4, math.min(10, math.floor(vim.o.lines * 0.35)))
	return math.min(max_height, math.max(4, rows))
end

local function set_buffer_options(buf)
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "markdown"
end

local function set_window_options(win)
	local options = {
		wrap = true,
		linebreak = true,
		breakindent = true,
		scrolloff = 0,
		sidescrolloff = 0,
		scrollbind = false,
		cursorbind = false,
		diff = false,
		number = false,
		relativenumber = false,
		signcolumn = "no",
		foldcolumn = "0",
		winhighlight = table.concat({
			"NormalFloat:UnifiedReviewInlineComposer",
			"FloatBorder:UnifiedReviewInlineBorder",
			"FloatTitle:UnifiedReviewInlineHeader",
			"FloatFooter:UnifiedReviewInlineMeta",
		}, ","),
	}
	for name, value in pairs(options) do
		pcall(vim.api.nvim_set_option_value, name, value, { win = win, scope = "local" })
	end
end

function M.open(opts)
	opts = opts or {}
	local session = manager.active()
	if not session then
		vim.notify("No active review session", vim.log.levels.INFO, { title = "unified-review" })
		return nil
	end
	if session._comment_editor_close then
		session._comment_editor_close()
	end

	local thread = opts.thread_id and thread_for(session, opts.thread_id) or nil
	if opts.thread_id and not thread then
		vim.notify("Review thread not found: " .. opts.thread_id, vim.log.levels.ERROR, { title = "unified-review" })
		return nil
	end
	local target = opts.target or (thread and thread.target)
	if not target then
		vim.notify("No comment target at cursor", vim.log.levels.INFO, { title = "unified-review" })
		return nil
	end

	local win, target_buf = target_window(session, target)
	if not (win and target_buf and vim.api.nvim_buf_is_valid(target_buf)) then
		vim.notify("Open the target file in the review diff before commenting", vim.log.levels.INFO, {
			title = "unified-review",
		})
		return nil
	end

	local previous_win = vim.api.nvim_get_current_win()
	local previous_cursor = previous_win
			and vim.api.nvim_win_is_valid(previous_win)
			and vim.api.nvim_win_get_cursor(previous_win)
		or nil
	local target_row = math.max(1, tonumber(target.line or target.start_line) or 1)
	local line_count = math.max(1, vim.api.nvim_buf_line_count(target_buf))
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_cursor(win, { math.min(target_row, line_count), 0 })
	pcall(vim.cmd, "normal! zz")

	local buf = vim.api.nvim_create_buf(false, true)
	set_buffer_options(buf)
	pcall(vim.api.nvim_buf_set_name, buf, "unified-review://comment/" .. tostring((vim.uv or vim.loop).hrtime()))
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.prefill or { "" })

	local editor = {
		target = target,
		body_height = 4,
		total_height = 6,
	}
	session._inline_editor = editor
	session._comment_editor_open = true
	inline.place(session)

	local geometry = editor.geometry
	if not geometry then
		session._inline_editor = nil
		session._comment_editor_open = false
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		vim.notify("Unable to place the comment editor at this diff location", vim.log.levels.ERROR, {
			title = "unified-review",
		})
		return nil
	end

	local title_text = opts.thread_id and "Reply" or ("Comment · " .. comment_target.label(target))
	local footer_text = " <C-s> save · Esc cancel "
	local closing = false
	local saved = false
	local autocmd_group
	local editor_win

	local function window_config()
		local current = editor.geometry
		if not current then
			return nil
		end
		local total_width = math.max(20, current.width)
		return {
			relative = "win",
			win = win,
			bufpos = { current.row, 0 },
			row = 1 + current.row_offset,
			col = 0,
			width = math.max(1, total_width - 2),
			height = editor.body_height,
			style = "minimal",
			focusable = true,
			noautocmd = true,
			zindex = 200,
			border = "single",
			title = " " .. truncate(title_text, math.max(1, total_width - 6)) .. " ",
			title_pos = "left",
			footer = truncate(footer_text, math.max(1, total_width - 4)),
			footer_pos = "right",
		}
	end

	local function refresh_layout()
		if closing or not vim.api.nvim_win_is_valid(win) then
			return
		end
		local width = editor.geometry and math.max(1, editor.geometry.width - 4) or 72
		local next_height = editor_body_height(buf, width)
		if next_height ~= editor.body_height then
			editor.body_height = next_height
			editor.total_height = next_height + 2
		end
		inline.place(session)
		local config = window_config()
		if config and editor_win and vim.api.nvim_win_is_valid(editor_win) then
			pcall(vim.api.nvim_win_set_config, editor_win, config)
			pcall(vim.api.nvim_win_set_height, editor_win, editor.body_height)
		end
	end

	local initial_width = math.max(1, geometry.width - 4)
	editor.body_height = editor_body_height(buf, initial_width)
	editor.total_height = editor.body_height + 2
	inline.place(session)
	local config = window_config()
	if not config then
		session._inline_editor = nil
		session._comment_editor_open = false
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		return nil
	end
	editor_win = vim.api.nvim_open_win(buf, true, config)
	set_window_options(editor_win)

	local function close_editor()
		if closing then
			return
		end
		closing = true
		pcall(vim.cmd, "stopinsert")
		if autocmd_group then
			pcall(vim.api.nvim_del_augroup_by_id, autocmd_group)
		end
		if session._comment_editor_window == editor_win then
			session._comment_editor_open = false
			session._comment_editor_window = nil
			session._comment_editor_buffer = nil
			session._comment_editor_close = nil
			session._inline_editor = nil
		end
		if editor_win and vim.api.nvim_win_is_valid(editor_win) then
			pcall(vim.api.nvim_win_close, editor_win, true)
		end
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
		if session.closed then
			inline.clear(session)
		else
			inline.place(session)
		end
		if previous_win and vim.api.nvim_win_is_valid(previous_win) then
			vim.api.nvim_set_current_win(previous_win)
			if previous_cursor then
				pcall(vim.api.nvim_win_set_cursor, previous_win, previous_cursor)
			end
		end
	end

	session._comment_editor_window = editor_win
	session._comment_editor_buffer = buf
	session._comment_editor_close = close_editor

	local function save(save_opts)
		save_opts = save_opts or {}
		if saved then
			if vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].modified = false
			end
			return true
		end
		local body = table.concat(body_lines(buf), "\n")
		local result, err
		if opts.thread_id then
			result, err = manager.reply(opts.thread_id, body)
		else
			result, err = manager.create_comment(body, target)
		end
		if not result then
			vim.notify(err and err.message or "Failed to save review comment", vim.log.levels.ERROR, {
				title = "unified-review",
			})
			return false
		end
		saved = true
		vim.bo[buf].modified = false
		if save_opts.defer_close then
			vim.schedule(close_editor)
		else
			close_editor()
		end
		return true
	end

	local function cancel()
		if not saved then
			vim.notify("Cancelled review comment", vim.log.levels.INFO, { title = "unified-review" })
		end
		close_editor()
	end

	vim.keymap.set("n", "q", cancel, { buffer = buf, silent = true })
	vim.keymap.set({ "n", "i" }, "<Esc>", cancel, { buffer = buf, silent = true })
	vim.keymap.set({ "n", "i", "x" }, "<C-s>", save, { buffer = buf, silent = true })
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			save({ defer_close = true })
		end,
	})
	autocmd_group = vim.api.nvim_create_augroup("unified_review_inline_editor_" .. tostring(buf), { clear = true })
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = autocmd_group,
		buffer = buf,
		callback = function()
			vim.schedule(refresh_layout)
		end,
	})
	vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
		group = autocmd_group,
		callback = function()
			vim.schedule(refresh_layout)
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = autocmd_group,
		pattern = tostring(editor_win),
		callback = function()
			if not closing then
				vim.schedule(close_editor)
			end
		end,
	})

	vim.api.nvim_win_set_cursor(editor_win, { math.max(1, vim.api.nvim_buf_line_count(buf)), 0 })
	vim.cmd("startinsert")
	return {
		buffer = buf,
		window = editor_win,
		save = save,
		cancel = cancel,
		body_lines = function()
			return body_lines(buf)
		end,
	}
end

function M.close(session)
	session = session or manager.active()
	if session and session._comment_editor_close then
		session._comment_editor_close()
		return true
	end
	return false
end

return M
