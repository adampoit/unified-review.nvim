local comment_target = require("unified_review.domain.comment_target")
local float = require("unified_review.ui.float")
local manager = require("unified_review.session.manager")

local M = {}

local function body_lines(buf, header_count)
	local lines = vim.api.nvim_buf_get_lines(buf, header_count, -1, false)
	while #lines > 0 and lines[1] == "" do
		table.remove(lines, 1)
	end
	while #lines > 0 and lines[#lines] == "" do
		table.remove(lines, #lines)
	end
	return lines
end

function M.open(opts)
	opts = opts or {}
	local session = manager.active()
	if session then
		session._comment_editor_open = true
	end
	local previous_win = vim.api.nvim_get_current_win()
	local header = opts.thread_id and ("Reply to " .. opts.thread_id)
		or ("Comment on " .. comment_target.label(opts.target))
	local lines = opts.prefill or { "" }
	local popup = float.open({
		name = "unified-review://comment/" .. tostring(vim.loop.hrtime()),
		lines = lines,
		filetype = "markdown",
		modifiable = true,
		buf_options = { buftype = "acwrite", bufhidden = "wipe", swapfile = false },
		win_options = {
			wrap = true,
			linebreak = true,
			breakindent = true,
			scrolloff = 0,
			sidescrolloff = 0,
			scrollbind = false,
			cursorbind = false,
			diff = false,
		},
		min_width = 72,
		height = math.min(12, math.max(1, math.floor(vim.o.lines * 0.5))),
		max_width = math.floor(vim.o.columns * 0.7),
		max_height = math.floor(vim.o.lines * 0.7),
		zindex_key = "comment_editor",
		title = header,
		default_keymaps = false,
		footer = { "[:w/<C-s>] save", "[q/Esc] cancel" },
	})
	local win = popup.window
	local buf = popup.buffer

	local closing = false
	local saved = false
	local first_input_received = false

	local function focus_editor()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_current_win(win)
			vim.api.nvim_win_set_cursor(win, { math.max(1, vim.api.nvim_buf_line_count(buf)), 0 })
		end
	end

	local function focus_editor_insert()
		focus_editor()
		if vim.api.nvim_get_current_buf() == buf then
			vim.cmd("startinsert")
		end
	end

	if session then
		session._comment_editor_window = win
		session._comment_editor_buffer = buf
	end

	focus_editor_insert()
	vim.schedule(function()
		if not closing and not first_input_received then
			focus_editor_insert()
		end
	end)
	vim.defer_fn(function()
		if not closing and not first_input_received then
			focus_editor_insert()
		end
	end, 25)
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = buf,
		callback = function()
			first_input_received = true
		end,
	})

	local function close_window()
		closing = true
		if session then
			session._comment_editor_open = false
			session._comment_editor_window = nil
			session._comment_editor_buffer = nil
		end
		popup.close()
		if previous_win and vim.api.nvim_win_is_valid(previous_win) then
			vim.api.nvim_set_current_win(previous_win)
		end
	end

	local function save(save_opts)
		save_opts = save_opts or {}
		if saved then
			if vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].modified = false
			end
			return true
		end

		local body = table.concat(body_lines(buf, 0), "\n")
		local result, err
		if opts.thread_id then
			result, err = manager.reply(opts.thread_id, body)
		else
			result, err = manager.create_comment(body, opts.target)
		end
		if not result then
			vim.notify(
				err and err.message or "failed to save review comment",
				vim.log.levels.ERROR,
				{ title = "unified-review" }
			)
			return false
		end
		saved = true
		vim.bo[buf].modified = false
		local message = opts.thread_id and "Created draft reply"
			or ("Created draft comment at " .. comment_target.label(result.target))
		local function notify_saved()
			vim.notify(message, vim.log.levels.INFO, { title = "unified-review" })
		end
		if save_opts.defer_close then
			vim.schedule(function()
				close_window()
				notify_saved()
			end)
		else
			close_window()
			notify_saved()
		end
		return true
	end

	local function cancel()
		if not saved then
			vim.notify("Cancelled review comment", vim.log.levels.INFO, { title = "unified-review" })
		end
		close_window()
	end

	vim.keymap.set("n", "q", cancel, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, silent = true })
	vim.keymap.set({ "n", "i", "x" }, "<C-s>", save, { buffer = buf, silent = true })
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			save({ defer_close = true })
		end,
	})
	return {
		buffer = buf,
		save = save,
		cancel = cancel,
		body_lines = function()
			return body_lines(buf, 0)
		end,
	}
end

return M
