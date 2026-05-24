local navigation = require("unified_review.ui.navigation")
local state = require("unified_review.session.state")

describe("ui navigation", function()
	after_each(function()
		state.clear_active()
	end)

	local function buffer()
		return vim.api.nvim_create_buf(false, true)
	end

	it("moves between files and rerenders diff buffers", function()
		local left_buf = buffer()
		local right_buf = buffer()
		local session = {
			editable = true,
			selection = { file_index = 1, hunk_index = 1 },
			files = {
				{
					status = "modified",
					path = "a.lua",
					hunks = { { header = "@@ a @@", lines = { { kind = "added", text = "a" } } } },
				},
				{
					status = "modified",
					path = "b.lua",
					hunks = { { header = "@@ b @@", lines = { { kind = "added", text = "b" } } } },
				},
			},
			ui = { left_buffer = left_buf, right_buffer = right_buf },
		}
		state.set_active(session)

		navigation.next_file()

		assert.are.equal(2, session.selection.file_index)
		local right_content = vim.api.nvim_buf_get_lines(right_buf, 0, 1, false)
		assert.are.equal(1, #right_content)
	end)

	it("moves to selected thread targets", function()
		local left_buf = buffer()
		local right_buf = buffer()
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "@@", "+ x" })
		local left_win = vim.api.nvim_get_current_win()
		local right_win =
			vim.api.nvim_open_win(right_buf, false, { relative = "editor", row = 1, col = 1, width = 20, height = 5 })
		local session = {
			selection = { file_index = 1 },
			files = {
				{
					path = "a.lua",
					hunks = { { header = "@@", lines = { { kind = "added", new_line = 7, text = "x" } } } },
				},
			},
			threads = { { id = "thread-1", target = { kind = "line", path = "a.lua", side = "right", line = 7 } } },
			ui = { left_buffer = left_buf, right_buffer = right_buf, left_window = left_win, right_window = right_win },
		}
		state.set_active(session)

		local thread = navigation.next_thread()
		if not thread then
			error("expected thread to be found")
		end
		assert.are.equal("thread-1", thread.id)
		assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(right_win))
		vim.api.nvim_win_close(right_win, true)
	end)
end)
