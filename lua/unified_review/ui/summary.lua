local renderer = require("components.renderer")
local export = require("unified_review.export")
local review_thread = require("unified_review.domain.review_thread")
local manager = require("unified_review.session.manager")

local M = {}

M.ns = vim.api.nvim_create_namespace("unified_review_summary")

local function active_session()
	local session = manager.active()
	if not session then
		vim.notify("No active review session", vim.log.levels.INFO, { title = "unified-review" })
		return nil
	end
	return session
end

local function review_text(format, session)
	return export.format(manager.list_threads() or {}, { format = format or "markdown", session = session })
end

local function summary_lines(session)
	local text = review_text("markdown", session)
	if text == "" then
		text = "# Code Review\n\nNo review threads."
	end
	return vim.split(text, "\n", { plain = true })
end

local function count_exported(threads)
	local count = 0
	for _, thread in ipairs(threads or {}) do
		if review_thread.is_exported(thread) then
			count = count + 1
		end
	end
	return count
end

function M.save_active(path, format)
	local session = manager.active()
	if not session then
		return nil, { message = "No active review session" }
	end
	path = path or vim.fn.getcwd() .. "/review.md"
	format = format or "markdown"
	local threads, list_err = manager.list_threads()
	if not threads then
		return nil, list_err or { message = "failed to list review threads" }
	end
	local ok, text_or_err = pcall(export.save, path, threads, { format = format, session = session })
	if not ok then
		return nil, { message = tostring(text_or_err) }
	end
	local text = text_or_err or ""
	return {
		path = path,
		format = format,
		bytes = #text,
		thread_count = #threads,
		exported_thread_count = count_exported(threads),
		empty = text == "",
	},
		nil
end

function M.copy(format)
	local session = active_session()
	if not session then
		return nil
	end
	local text = export.copy(manager.list_threads() or {}, { format = format or "markdown", session = session })
	vim.notify(
		string.format("Copied %d character(s) of review text", #text),
		vim.log.levels.INFO,
		{ title = "unified-review" }
	)
	return text
end

function M.save(path, format)
	local result, err = M.save_active(path, format)
	vim.g.unified_review_last_save = result or vim.NIL
	vim.g.unified_review_last_save_error = err or vim.NIL
	if result then
		vim.notify("Saved review to " .. result.path, vim.log.levels.INFO, { title = "unified-review" })
	else
		vim.notify(
			"Failed to save review: " .. (err and err.message or "unknown error"),
			vim.log.levels.ERROR,
			{ title = "unified-review" }
		)
	end
	return result ~= nil
end

local function set_summary_keymaps(buf)
	vim.keymap.set("n", "y", function()
		M.copy("markdown")
	end, { buffer = buf, noremap = true, silent = true })
	vim.keymap.set("n", "w", function()
		vim.ui.input({ prompt = "Save review to: ", default = vim.fn.getcwd() .. "/review.md" }, function(path)
			if path and path ~= "" then
				M.save(path, "markdown")
			end
		end)
	end, { buffer = buf, noremap = true, silent = true })
	vim.keymap.set("n", "q", function()
		local win = vim.api.nvim_get_current_win()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end, { buffer = buf, noremap = true, silent = true })
end

function M.open()
	local session = active_session()
	if not session then
		return nil
	end
	session.ui = session.ui or {}
	if session.ui.summary_win and vim.api.nvim_win_is_valid(session.ui.summary_win) then
		vim.api.nvim_set_current_win(session.ui.summary_win)
		M.render(session)
		return { buffer = session.ui.summary_buf, window = session.ui.summary_win }
	end

	vim.cmd("botright split")
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(win, buf)
	pcall(vim.api.nvim_buf_set_name, buf, "unified-review://summary")
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "markdown"
	vim.wo[win].winbar = "Review Summary"
	session.ui.summary_buf = buf
	session.ui.summary_win = win
	set_summary_keymaps(buf)
	M.render(session)
	return { buffer = buf, window = win }
end

function M.render(session)
	session = session or active_session()
	if not session or not session.ui or not session.ui.summary_buf then
		return
	end
	local buf = session.ui.summary_buf
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.bo[buf].modifiable = true
	renderer.render(buf, M.ns, summary_lines(session))
	vim.bo[buf].modifiable = false
end

function M.close(session)
	session = session or manager.active()
	if not session or not session.ui or not session.ui.summary_buf then
		return false
	end
	local win = session.ui.summary_win
	local buf = session.ui.summary_buf
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
	if buf and vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
	session.ui.summary_buf = nil
	session.ui.summary_win = nil
	return true
end

return M
