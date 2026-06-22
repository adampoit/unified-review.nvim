local signs = require("unified_review.ui.signs")

describe("ui signs", function()
	before_each(function()
		-- clear any existing signs/extmarks between tests
	end)

	it("places draft thread signs at the target line", function()
		local left = vim.api.nvim_create_buf(false, true)
		local right = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right, 0, -1, false, { "changed content line" })
		local session = {
			ui = { left_buffer = left, right_buffer = right },
			selection = { file_index = 1 },
			files = {
				{
					path = "a.lua",
					hunks = {
						{
							header = "@@ -1 +1 @@",
							old_start = 1,
							new_start = 1,
							lines = { { kind = "added", new_line = 1, text = "changed content line" } },
						},
					},
				},
			},
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "a.lua", side = "right", line = 1 },
					comments = { { state = "draft", body = "looks good" } },
				},
			},
		}

		signs.place(session)
		local placed = vim.fn.sign_getplaced(right, { group = "unified_review_threads" })[1].signs
		assert.are.equal(2, #placed)
		local by_name = {}
		for _, sign in ipairs(placed) do
			by_name[sign.name] = sign
		end
		assert.is_not_nil(by_name.UnifiedReviewDraft)
		assert.is_not_nil(by_name.UnifiedReviewExported)
		assert.are.equal(1, by_name.UnifiedReviewDraft.lnum)

		signs.clear(session)
		placed = vim.fn.sign_getplaced(right, { group = "unified_review_threads" })[1].signs
		assert.are.equal(0, #placed)
	end)

	it("places signs on every row in a range target with range brackets", function()
		local left = vim.api.nvim_create_buf(false, true)
		local right = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right, 0, -1, false, { "one", "two", "three" })
		local session = {
			ui = { left_buffer = left, right_buffer = right },
			selection = { file_index = 1 },
			files = { { path = "a.lua", hunks = {} } },
			threads = {
				{
					state = "open",
					target = {
						kind = "range",
						path = "a.lua",
						start_side = "right",
						start_line = 1,
						side = "right",
						line = 3,
					},
					comments = { { state = "draft", body = "range comment" } },
				},
			},
		}

		signs.place(session)
		local placed = vim.fn.sign_getplaced(right, { group = "unified_review_threads" })[1].signs
		assert.are.equal(4, #placed)
		local by_name = {}
		for _, sign in ipairs(placed) do
			by_name[sign.name] = sign
		end
		assert.are.equal(1, by_name.UnifiedReviewRangeTop.lnum)
		assert.are.equal(3, by_name.UnifiedReviewRangeBot.lnum)
		-- range signs should use bracket glyphs, not the thread-state icon
		assert.is_not_nil(by_name.UnifiedReviewRangeTop)
		assert.is_not_nil(by_name.UnifiedReviewRangeMid)
		assert.is_not_nil(by_name.UnifiedReviewRangeBot)
		assert.is_not_nil(by_name.UnifiedReviewExported)
	end)

	it("does not render stale thread signs in diff buffers", function()
		local left = vim.api.nvim_create_buf(false, true)
		local right = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right, 0, -1, false, { "one", "two" })
		local session = {
			ui = { left_buffer = left, right_buffer = right },
			selection = { file_index = 1 },
			files = { { path = "a.lua", hunks = {} } },
			threads = {
				{
					state = "stale",
					target = { kind = "line", path = "a.lua", side = "right", line = 1 },
					comments = { { body = "gone" } },
				},
				{
					state = "open",
					is_outdated = true,
					target = { kind = "line", path = "a.lua", side = "right", line = 2 },
					comments = { { body = "outdated" } },
				},
			},
		}

		signs.place(session)

		local placed = vim.fn.sign_getplaced(right, { group = "unified_review_threads" })[1].signs
		assert.are.equal(0, #placed)
	end)

	it("does not place diff gutter signs", function()
		local left = vim.api.nvim_create_buf(false, true)
		local right = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left, 0, -1, false, { "old" })
		vim.api.nvim_buf_set_lines(right, 0, -1, false, { "new" })
		local session = {
			ui = { left_buffer = left, right_buffer = right },
			selection = { file_index = 1 },
			files = {
				{
					path = "a.lua",
					hunks = {
						{ lines = { { kind = "deleted", old_line = 1 }, { kind = "added", new_line = 1 } } },
					},
				},
			},
			threads = {},
		}

		signs.place(session)

		local left_diff = vim.fn.sign_getplaced(left, { group = "unified_review_diff" })[1].signs
		local right_diff = vim.fn.sign_getplaced(right, { group = "unified_review_diff" })[1].signs
		assert.are.equal(0, #left_diff)
		assert.are.equal(0, #right_diff)
	end)
end)
