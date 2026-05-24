local M = {}

function M.close(session)
	if not session then
		return
	end
	session.closed = true
	pcall(require("unified_review.ui.signs").clear, session)
	pcall(require("unified_review.ui.thread_panel").close, session)
	pcall(require("unified_review.ui.summary").close, session)
	if session.ui_autocmd_group then
		pcall(vim.api.nvim_del_augroup_by_id, session.ui_autocmd_group)
	end
	if session.ui and session.ui.codediff_tab then
		pcall(require("codediff.ui.lifecycle").cleanup, session.ui.codediff_tab)
	end
	if session.ui then
		for _, win in ipairs(session.ui.windows or {}) do
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
		if not session.ui.codediff_tab then
			for _, buf in ipairs(session.ui.buffers or {}) do
				if vim.api.nvim_buf_is_valid(buf) then
					vim.api.nvim_buf_delete(buf, { force = true })
				end
			end
		end
	end
end

return M
