local loading = require("unified_review.ui.loading")

describe("loading float", function()
	local active_loading

	after_each(function()
		if active_loading then
			active_loading:close()
			active_loading = nil
		end
	end)

	it("renders and closes an animated loading popup", function()
		local state = loading.open({ message = "Loading GitHub PR #123", interval = 20 })
		active_loading = state

		local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
		assert.matches("Loading GitHub PR #123", table.concat(lines, "\n"))
		assert.is_true(vim.api.nvim_win_is_valid(state.win))

		assert.is_true(vim.wait(200, function()
			return state.frame > 0
		end))

		state:close()
		assert.is_false(vim.api.nvim_win_is_valid(state.win))
	end)
end)
