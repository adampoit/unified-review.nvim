local git_repo = require("tests.helpers.git_repo")
local manager = require("unified_review.session.manager")
local picker = require("unified_review.ui.target_picker")
local session_state = require("unified_review.session.state")

local function press(state, lhs)
	for _, map in ipairs(vim.api.nvim_buf_get_keymap(state.buf, "n")) do
		if map.lhs == lhs then
			map.callback()
			return
		end
	end
	error("missing picker keymap " .. lhs)
end

describe("target picker integration", function()
	local original_cwd

	before_each(function()
		original_cwd = vim.fn.getcwd()
	end)

	after_each(function()
		picker.close_current()
		if session_state.get_active() then
			manager.close()
		end
		if original_cwd then
			vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
		end
	end)

	it(":UnifiedReview opens the picker and selecting a target opens a review session", function()
		require("unified_review").setup({})
		local root = git_repo.create()
		git_repo.write(root, "a.lua", { "return 1" })
		git_repo.commit(root, "base")
		git_repo.write(root, "a.lua", { "return 2" })
		vim.cmd("cd " .. vim.fn.fnameescape(root))

		vim.cmd("UnifiedReview")
		local state = assert(picker.current)
		assert.are.equal("list", state.mode)
		assert.matches("Working tree changes", table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n"))

		press(state, "<CR>")
		local active = assert(session_state.get_active())

		assert.are.equal("git_local", active.provider)
		assert.are.equal("WORKING", active.target.head)
		assert.is_true(#active.files > 0)
	end)
end)
