local M = {}

function M.setup_buffer(buf, opts)
	opts = opts or {}
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	if opts.name then
		pcall(vim.api.nvim_buf_set_name, buf, opts.name)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines or { "" })
	vim.bo[buf].modified = false
end

function M.activate(buf)
	vim.bo[buf].filetype = "markdown"
end

function M.set_keymaps(buf, actions)
	vim.keymap.set("n", "q", actions.cancel, { buffer = buf, silent = true })
	vim.keymap.set({ "n", "i", "x" }, "<C-s>", actions.save, { buffer = buf, silent = true })
end

return M
