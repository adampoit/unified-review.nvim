local diff_view = require("unified_review.ui.diff_view")

describe("diff view", function()
	describe("review keymaps", function()
		after_each(function()
			pcall(vim.cmd, "silent! nunmap <buffer> <leader>rc")
			pcall(vim.cmd, "silent! xunmap <buffer> <leader>rc")
		end)

		it("installs add-comment mappings in normal and visual modes", function()
			local left_buf = vim.api.nvim_create_buf(false, true)
			local right_buf = vim.api.nvim_create_buf(false, true)
			local session = {
				ui = { left_buffer = left_buf, right_buffer = right_buf },
				files = { { path = "a.lua", hunks = {} } },
				selection = { file_index = 1 },
				threads = {},
			}

			diff_view._attach_review_keymaps(session)

			local normal_maps = vim.api.nvim_buf_get_keymap(right_buf, "n")
			local visual_maps = vim.api.nvim_buf_get_keymap(right_buf, "x")
			local function has_comment_map(maps)
				for _, map in ipairs(maps) do
					if map.lhs == "\\rc" or map.lhs == "<leader>rc" then
						return true
					end
				end
				return false
			end
			assert.is_true(has_comment_map(normal_maps))
			assert.is_true(has_comment_map(visual_maps))
		end)
	end)

	describe("focus_hunk", function()
		it("sets cursor to hunk start row in the appropriate buffer", function()
			local left_buf = vim.api.nvim_create_buf(false, true)
			local right_buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, { "line1", "line2", "line3", "line4" })
			vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "line1", "line2", "line3", "line4" })

			local left_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(left_win, left_buf)
			vim.cmd("vsplit")
			local right_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(right_win, right_buf)

			local session = {
				ui = {
					left_buffer = left_buf,
					right_buffer = right_buf,
					left_window = left_win,
					right_window = right_win,
				},
				selection = { file_index = 1, hunk_index = 2 },
				files = {
					{
						path = "a.lua",
						hunks = {
							{ header = "@@ -1 +1 @@", old_start = 1, new_start = 1, lines = {} },
							{ header = "@@ -3 +3 @@", old_start = 3, new_start = 3, lines = {} },
						},
					},
				},
			}

			-- Focus hunk 2 from the right window.
			vim.api.nvim_set_current_win(right_win)
			diff_view.focus_hunk(session)
			assert.are.equal(3, vim.api.nvim_win_get_cursor(right_win)[1])

			-- Focus hunk 1 from the left window.
			vim.api.nvim_set_current_win(left_win)
			session.selection.hunk_index = 1
			diff_view.focus_hunk(session)
			assert.are.equal(1, vim.api.nvim_win_get_cursor(left_win)[1])
		end)
	end)
end)
