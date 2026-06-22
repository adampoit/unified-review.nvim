local selection = require("unified_review.session.selection")

describe("session selection", function()
	it("initializes and navigates files", function()
		local session = { files = { { path = "a.lua", hunks = {} }, { path = "b.lua", hunks = {} } } }

		selection.initialize(session)
		assert.are.equal("a.lua", selection.current_file(session).path)
		assert.are.equal("b.lua", selection.next_file(session).path)
		assert.are.equal("a.lua", selection.previous_file(session).path)
	end)

	it("navigates hunks within the selected file", function()
		local session = { files = { { path = "a.lua", hunks = { { header = "one" }, { header = "two" } } } } }

		selection.initialize(session)
		assert.are.equal("one", selection.current_hunk(session).header)
		assert.are.equal("two", selection.next_hunk(session).header)
		assert.are.equal("one", selection.previous_hunk(session).header)
	end)

	it("maps rendered diff rows to comment targets", function()
		local session = {
			files = {
				{
					path = "a.lua",
					hunks = {
						{
							header = "@@ -1,2 +1,2 @@",
							lines = {
								{ kind = "context", old_line = 1, new_line = 1 },
								{ kind = "deleted", old_line = 2 },
								{ kind = "added", new_line = 2 },
							},
						},
					},
				},
			},
		}
		selection.initialize(session)

		assert.are.same(
			{ kind = "line", path = "a.lua", side = "right", line = 2 },
			selection.target_for_row(session, 2, "right")
		)
		assert.are.same(
			{ kind = "line", path = "a.lua", side = "left", line = 2 },
			selection.target_for_row(session, 2, "left")
		)
		assert.are.same(
			{ kind = "line", path = "a.lua", side = "right", line = 1 },
			selection.target_for_row(session, 1, "right")
		)
		assert.are.equal(
			2,
			selection.row_for_target(session, { kind = "line", path = "a.lua", side = "right", line = 2 }, "right")
		)
		assert.are.same({
			kind = "range",
			path = "a.lua",
			start_side = "right",
			start_line = 1,
			side = "right",
			line = 2,
		}, selection.target_for_range(session, 1, 2, "right"))
		assert.is_nil(selection.target_for_range(session, 0, 0, "right"))
	end)

	it("builds a file target from the codediff explorer", function()
		local explorer_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(explorer_buf)
		local session = {
			files = { { path = "added.lua", hunks = {} }, { path = "other.lua", hunks = {} } },
			selection = { file_index = 2 },
			ui = {
				codediff_session = {
					explorer = {
						bufnr = explorer_buf,
						tree = {
							get_node = function()
								return { data = { path = "added.lua", status = "A" } }
							end,
						},
					},
				},
			},
		}

		assert.are.same({ kind = "file", path = "added.lua" }, selection.ensure_comment_target(session))
		assert.are.equal(1, session.selection.file_index)
	end)

	it("uses the existing side for one-sided files", function()
		local session = {
			files = {
				{ path = "added.lua", status = "added", hunks = {} },
				{ path = "deleted.lua", status = "deleted", hunks = {} },
			},
			selection = { file_index = 1 },
		}

		assert.are.same(
			{ kind = "line", path = "added.lua", side = "right", line = 3 },
			selection.target_for_row(session, 3, "left")
		)
		assert.are.same({
			kind = "range",
			path = "added.lua",
			start_side = "right",
			start_line = 2,
			side = "right",
			line = 4,
		}, selection.target_for_range(session, 2, 4, "left"))

		session.selection.file_index = 2
		assert.are.same(
			{ kind = "line", path = "deleted.lua", side = "left", line = 5 },
			selection.target_for_row(session, 5, "right")
		)
	end)

	it("selects the visible one-sided CodeDiff file before creating a line target", function()
		local previous_lifecycle = package.loaded["codediff.ui.lifecycle"]
		package.loaded["codediff.ui.lifecycle"] = {
			get_session = function()
				return nil
			end,
			get_paths = function()
				return "", "/repo/added.lua"
			end,
		}

		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two" })
		local win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(win, buf)
		vim.api.nvim_win_set_cursor(win, { 2, 0 })

		local session = {
			target = { root = "/repo" },
			files = {
				{ path = "old.lua", status = "modified", hunks = {} },
				{ path = "added.lua", status = "added", hunks = {} },
			},
			selection = { file_index = 1 },
			ui = {
				codediff_tab = 1,
				right_buffer = buf,
				right_window = win,
			},
		}

		local ok, target = pcall(selection.ensure_comment_target, session)
		package.loaded["codediff.ui.lifecycle"] = previous_lifecycle
		assert.is_true(ok)
		assert.are.same({ kind = "line", path = "added.lua", side = "right", line = 2 }, target)
		assert.are.equal(2, session.selection.file_index)
	end)

	it("finds threads at the current target", function()
		local session = {
			files = { { path = "a.lua", hunks = {} } },
			selection = { file_index = 1 },
			threads = {
				{ id = "thread-1", target = { kind = "range", path = "a.lua", start_line = 4, line = 6 } },
				{ id = "thread-2", target = { kind = "line", path = "a.lua", line = 9 } },
			},
		}
		local function first_at_target(target)
			return selection.threads_at_target(session, target)[1]
		end
		assert.are.equal("thread-1", first_at_target({ kind = "line", path = "a.lua", line = 5 }).id)
		assert.are.equal("thread-2", first_at_target({ kind = "line", path = "a.lua", line = 9 }).id)
		assert.is_nil(first_at_target({ kind = "line", path = "a.lua", line = 7 }))
	end)

	it("surfaces all overlapping threads at a target", function()
		-- A multiline range comment and a single-line comment nested inside it.
		local session = {
			files = { { path = "a.lua", hunks = {} } },
			threads = {
				{ id = "thread-range", target = { kind = "range", path = "a.lua", start_line = 10, line = 15 } },
				{ id = "thread-single", target = { kind = "line", path = "a.lua", line = 12 } },
			},
		}

		local outer = selection.threads_at_target(session, { kind = "line", path = "a.lua", line = 10 })
		assert.are.same(
			{ "thread-range" },
			vim.tbl_map(function(t)
				return t.id
			end, outer)
		)

		-- Line 12 sits inside the range AND matches the single-line thread.
		local overlapping = selection.threads_at_target(session, { kind = "line", path = "a.lua", line = 12 })
		assert.are.same(
			{ "thread-range", "thread-single" },
			vim.tbl_map(function(t)
				return t.id
			end, overlapping)
		)
	end)

	it("navigates current-file threads", function()
		local session = {
			selection = { file_index = 1 },
			files = { { path = "a.lua", hunks = {} }, { path = "b.lua", hunks = {} } },
			threads = {
				{ id = "thread-1", target = { path = "a.lua" } },
				{ id = "thread-2", target = { path = "b.lua" } },
				{ id = "thread-3", target = { path = "a.lua" } },
			},
		}

		assert.are.equal("thread-1", selection.next_thread(session).id)
		assert.are.equal("thread-3", selection.next_thread(session).id)
		assert.are.equal("thread-1", selection.previous_thread(session).id)
	end)
end)
