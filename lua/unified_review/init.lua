local config = require("unified_review.config")
local commands = require("unified_review.commands")

local M = {}
local autocmds_registered = false

local function setup_codediff_autocmds()
	if autocmds_registered or not config.options.codediff.auto_attach then
		return
	end
	autocmds_registered = true
	local group = vim.api.nvim_create_augroup("unified_review_codediff_auto_attach", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "CodeDiffOpen",
		callback = function(event)
			vim.schedule(function()
				require("unified_review.session.manager").attach_codediff(
					event.data and event.data.tabpage,
					{ silent = true }
				)
			end)
		end,
	})
end

function M.setup(opts)
	M.config = config.setup(opts)
	commands.setup()
	pcall(require("unified_review.integrations.codediff_explorer").install)
	setup_codediff_autocmds()
	return M.config
end

return M
