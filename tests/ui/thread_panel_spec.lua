local thread_panel = require("unified_review.ui.thread_panel")
local state = require("unified_review.session.state")

local function text(lines)
	return table.concat(lines, "\n")
end

local function call_normal_map(buf, lhs)
	for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
		if map.lhs == lhs then
			map.callback()
			return true
		end
	end
	return false
end

local function has_comment_keymap(buf)
	for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
		if map.rhs == "<Cmd>UnifiedReview comment<CR>" then
			return true
		end
	end
	return false
end

local function make_session()
	return {
		selection = { file_index = 1, thread_index = 1 },
		files = {
			{ status = "modified", path = "a.lua", hunks = {} },
			{ status = "modified", path = "b.lua", hunks = {} },
		},
		threads = {
			{
				id = "thread-1",
				state = "open",
				target = { kind = "line", path = "a.lua", side = "right", line = 4 },
				comments = { { id = "c1", author = "alice", body = "consider renaming" } },
			},
			{
				id = "thread-2",
				state = "resolved",
				target = {
					kind = "range",
					path = "a.lua",
					start_line = 10,
					start_side = "right",
					line = 15,
					side = "right",
				},
				comments = { { id = "c2", author = "me", body = "fixed this range" } },
			},
			{
				id = "thread-3",
				state = "open",
				target = { kind = "file", path = "b.lua" },
				comments = { { id = "c3", author = "local", state = "draft", body = "overall: LGTM" } },
			},
		},
		ui = {},
	}
end

describe("thread panel", function()
	after_each(function()
		if thread_panel.is_open() then
			thread_panel.close()
		end
		state.clear_active()
	end)

	it("renders a project-wide review overview grouped by file", function()
		local session = make_session()

		local lines = thread_panel.render_lines(session)
		local rendered = text(lines)

		assert.matches("o/v/d/s/a  states", lines[1])
		local summary_row
		for index, line in ipairs(lines) do
			if line:match("Threads:") then
				summary_row = index
				break
			end
		end
		assert.is_not_nil(summary_row)
		assert.are.equal("", lines[summary_row - 1])
		assert.matches("Scope: project", rendered)
		assert.matches("a%.lua", rendered)
		assert.matches("b%.lua", rendered)
		assert.matches("L4", rendered)
		assert.matches("consider renaming", rendered)
		assert.matches("L10%-L15", rendered)
		assert.matches("fixed this range", rendered)
		assert.matches("File", rendered)
		assert.matches("LGTM", rendered)
	end)

	it("can scope the overview to the current file", function()
		local session = make_session()
		session._thread_scope = "current"

		local rendered = text(thread_panel.render_lines(session))

		assert.matches("Scope: current file", rendered)
		assert.matches("a%.lua", rendered)
		assert.not_matches("b%.lua", rendered)
		assert.matches("consider renaming", rendered)
		assert.not_matches("LGTM", rendered)
	end)

	it("filters threads by state", function()
		local session = make_session()
		session._thread_filter = { open = true, resolved = false, draft = false, stale = false }

		local rendered = text(thread_panel.render_lines(session))

		assert.matches("consider renaming", rendered)
		assert.not_matches("fixed this range", rendered)
		assert.not_matches("LGTM", rendered)
	end)

	it("shows stale warning for outdated threads", function()
		local session = {
			selection = { file_index = 1 },
			files = { { status = "modified", path = "x.lua", hunks = {} } },
			threads = {
				{
					id = "stale-1",
					state = "stale",
					is_outdated = true,
					target = { path = "x.lua", line = 1 },
					comments = { { body = "outdated comment" } },
				},
			},
		}

		local rendered = text(thread_panel.render_lines(session))

		assert.matches("⚠", rendered)
		assert.matches("stale", rendered)
		assert.matches("outdated comment", rendered)
	end)

	it("filters threads by plain text query and explains active filters", function()
		local session = make_session()
		session._thread_query = "alice consider"

		local header = thread_panel.render_filter_lines(session)
		assert.matches("States:.*open", header[1])
		assert.matches("Scope: project", header[1])
		assert.matches("Query: alice consider", header[1])
		assert.matches("o/v/d/s/a  states", header[2])
		assert.not_matches("Keys:", header[2])
		local rendered = text(thread_panel.render_lines(session))
		assert.matches("consider renaming", rendered)
		assert.not_matches("fixed this range", rendered)
		assert.not_matches("LGTM", rendered)
	end)

	it("handles empty threads", function()
		local session = {
			selection = { file_index = 1 },
			files = { { status = "modified", path = "a.lua", hunks = {} } },
			threads = {},
		}

		local rendered = text(thread_panel.render_lines(session))
		assert.matches("No review threads", rendered)
	end)

	it("truncates long comment bodies", function()
		local long_body = string.rep("x", 90) .. "tail"
		local session = {
			selection = { file_index = 1 },
			files = { { status = "modified", path = "a.lua", hunks = {} } },
			threads = {
				{
					id = "t1",
					state = "open",
					target = { path = "a.lua", line = 1 },
					comments = { { body = long_body } },
				},
			},
		}

		local rendered = text(thread_panel.render_lines(session))
		assert.matches("%.%.%.", rendered)
		assert.not_matches("tail", rendered)
	end)

	it("handles suggestion blocks in comment body", function()
		local session = {
			selection = { file_index = 1 },
			files = { { status = "modified", path = "a.lua", hunks = {} } },
			threads = {
				{
					id = "t1",
					state = "open",
					target = { path = "a.lua", line = 1 },
					comments = { { body = "```suggestion\nlocal x = 1\n```" } },
				},
			},
		}

		local rendered = text(thread_panel.render_lines(session))
		assert.matches("%[suggestion block%]", rendered)
	end)

	it("previews the first meaningful comment line", function()
		local session = {
			selection = { file_index = 1 },
			files = { { status = "modified", path = "a.lua", hunks = {} } },
			threads = {
				{
					id = "t1",
					state = "open",
					target = { path = "a.lua", line = 1 },
					comments = { { body = "\n\n```lua\nlocal x = 1" } },
				},
			},
		}

		local rendered = text(thread_panel.render_lines(session))
		assert.matches("local x = 1", rendered)
	end)

	it("distinguishes local and remote draft labels", function()
		local session = make_session()
		session.kind = "github_pr"
		table.insert(session.threads, {
			id = "thread-4",
			state = "open",
			target = { kind = "line", path = "b.lua", side = "right", line = 8 },
			comments = {
				{
					id = "c4",
					author = "me",
					state = "draft",
					body = "already pushed",
					metadata = { github = { id = "c4" } },
				},
			},
		})

		local rendered = text(thread_panel.render_lines(session))

		assert.matches("local draft", rendered)
		assert.matches("remote draft", rendered)
		assert.matches("1 local", rendered)
		assert.matches("1 remote", rendered)
	end)

	it("renders a scrollable thread preview with all comments", function()
		local lines = thread_panel.render_thread_lines({
			id = "t1",
			state = "open",
			target = { kind = "line", path = "a.lua", line = 12 },
			comments = {
				{ author = "alice", body = "first\nbody" },
				{ author = "bob", body = "reply" },
			},
		})

		assert.matches("open", lines[1])
		assert.matches("L12", lines[2])
		assert.matches("a.lua", text(lines))
		assert.matches("alice", text(lines))
		assert.matches("first", text(lines))
		assert.matches("bob", text(lines))
		assert.matches("reply", text(lines))
	end)

	it("opens a normal scratch overview buffer and closes cleanly", function()
		local session = make_session()
		state.set_active(session)

		local ok = thread_panel.open()
		assert.is_true(ok)
		assert.is_true(thread_panel.is_open())
		assert.is_not_nil(session.ui.thread_panel_buf)
		assert.is_not_nil(session.ui.thread_panel_win)
		assert.is_nil(session.ui.thread_panel_prompt_buf)
		assert.is_nil(session.ui.thread_panel_filter_buf)

		assert.are.equal("nofile", vim.bo[session.ui.thread_panel_buf].buftype)
		assert.are.equal("unified-review", vim.bo[session.ui.thread_panel_buf].filetype)
		local lines = vim.api.nvim_buf_get_lines(session.ui.thread_panel_buf, 0, -1, false)
		local marks =
			vim.api.nvim_buf_get_extmarks(session.ui.thread_panel_buf, thread_panel.ns, 0, -1, { details = true })
		local saw_key = false
		local saw_section = false
		local saw_state = false
		for _, mark in ipairs(marks) do
			local details = mark[4] or {}
			if details.hl_group == "UnifiedReviewThreadsKey" then
				saw_key = true
			elseif details.hl_group == "UnifiedReviewThreadsSection" then
				saw_section = true
			elseif details.hl_group == "UnifiedReviewThreadsOpen" then
				saw_state = true
			end
		end
		assert.not_matches("Review Overview", text(lines))
		assert.matches("consider renaming", text(lines))
		assert.is_true(saw_key)
		assert.is_true(saw_section)
		assert.is_true(saw_state)

		local closed = thread_panel.close()
		assert.is_true(closed)
		assert.is_false(thread_panel.is_open())
		assert.is_nil(session.ui.thread_panel_buf)
	end)

	it("moves selection with list-style navigation instead of cursor roaming", function()
		local session = make_session()
		state.set_active(session)
		thread_panel.open()

		assert.are.equal("thread-1", session._thread_selected_id)
		assert.is_true(call_normal_map(session.ui.thread_panel_buf, "j"))

		assert.are.equal("thread-2", session._thread_selected_id)
		local cursor_row = vim.api.nvim_win_get_cursor(session.ui.thread_panel_win)[1]
		local entry = session.ui.thread_panel_rows[cursor_row]
		assert.are.equal("thread", entry.kind)
		assert.are.equal("thread-2", entry.thread.id)
		assert.is_true(entry.selected)
	end)

	it("moves selection in the rendered file order", function()
		local session = make_session()
		session.files = {
			{ status = "modified", path = "b.lua", hunks = {} },
			{ status = "modified", path = "a.lua", hunks = {} },
		}
		state.set_active(session)
		thread_panel.open()

		assert.are.equal("thread-3", session._thread_selected_id)
		assert.is_true(call_normal_map(session.ui.thread_panel_buf, "j"))
		assert.are.equal("file:a.lua", session._thread_selected_key)
		assert.is_nil(session._thread_selected_id)
		assert.is_true(call_normal_map(session.ui.thread_panel_buf, "j"))
		assert.are.equal("thread-1", session._thread_selected_id)
	end)

	it("keeps file headers selectable so collapsed groups can be expanded", function()
		local session = make_session()
		state.set_active(session)
		thread_panel.open()

		assert.is_true(call_normal_map(session.ui.thread_panel_buf, "k"))
		local cursor_row = vim.api.nvim_win_get_cursor(session.ui.thread_panel_win)[1]
		local entry = session.ui.thread_panel_rows[cursor_row]
		assert.are.equal("file", entry.kind)
		assert.are.equal("a.lua", entry.path)
		assert.are.equal("file:a.lua", session._thread_selected_key)
		assert.is_nil(session._thread_selected_id)

		assert.is_true(call_normal_map(session.ui.thread_panel_buf, "za"))
		assert.is_true(session._thread_file_collapsed["a.lua"])
		entry = session.ui.thread_panel_rows[vim.api.nvim_win_get_cursor(session.ui.thread_panel_win)[1]]
		assert.are.equal("file", entry.kind)
		assert.are.equal("a.lua", entry.path)
		local rendered = text(vim.api.nvim_buf_get_lines(session.ui.thread_panel_buf, 0, -1, false))
		assert.not_matches("consider renaming", rendered)
		assert.not_matches("fixed this range", rendered)

		assert.is_true(call_normal_map(session.ui.thread_panel_buf, "za"))
		assert.is_false(session._thread_file_collapsed["a.lua"])
		rendered = text(vim.api.nvim_buf_get_lines(session.ui.thread_panel_buf, 0, -1, false))
		assert.matches("consider renaming", rendered)
		assert.matches("fixed this range", rendered)
	end)

	it("jumps to a thread after CodeDiff replaces buffers and keeps review keymaps", function()
		local previous_view = package.loaded["codediff.ui.view"]
		local previous_lifecycle = package.loaded["codediff.ui.lifecycle"]
		local tabpage = vim.api.nvim_get_current_tabpage()
		local right_win = vim.api.nvim_get_current_win()
		local old_buf = vim.api.nvim_create_buf(false, true)
		local new_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(old_buf, 0, -1, false, { "old" })
		vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, { "1", "2", "3", "4", "5", "6", "7" })
		vim.api.nvim_win_set_buf(right_win, old_buf)

		local lifecycle_state = {
			left_buf = old_buf,
			right_buf = old_buf,
			left_win = nil,
			right_win = right_win,
			original_path = "a.lua",
			modified_path = "a.lua",
			session = {},
		}
		local captured_cfg
		local captured_auto_scroll
		package.loaded["codediff.ui.view"] = {
			update = function(_, cfg, auto_scroll_to_first_hunk)
				captured_cfg = cfg
				captured_auto_scroll = auto_scroll_to_first_hunk
				vim.schedule(function()
					lifecycle_state.right_buf = new_buf
					lifecycle_state.modified_path = "b.lua"
					vim.api.nvim_win_set_buf(right_win, new_buf)
				end)
				return true
			end,
		}
		package.loaded["codediff.ui.lifecycle"] = {
			get_buffers = function()
				return lifecycle_state.left_buf, lifecycle_state.right_buf
			end,
			get_windows = function()
				return lifecycle_state.left_win, lifecycle_state.right_win
			end,
			get_paths = function()
				return lifecycle_state.original_path, lifecycle_state.modified_path
			end,
			get_session = function()
				return lifecycle_state.session
			end,
		}

		local session = {
			id = "remote-thread-jump",
			target = { root = "/repo" },
			selection = { file_index = 1 },
			files = {
				{ status = "modified", path = "a.lua", hunks = {} },
				{ status = "modified", path = "b.lua", hunks = {} },
			},
			threads = {
				{
					id = "thread-b",
					state = "open",
					target = { kind = "line", path = "b.lua", side = "right", line = 7 },
					comments = { { id = "comment-b", author = "alice", body = "remote comment" } },
				},
			},
			ui = { codediff_tab = tabpage, right_buffer = old_buf, right_window = right_win },
		}
		state.set_active(session)
		assert.is_true(thread_panel.open(session))
		assert.is_true(call_normal_map(session.ui.thread_panel_buf, "<CR>"))

		local ok = vim.wait(500, function()
			return vim.api.nvim_get_current_win() == right_win
				and vim.api.nvim_win_get_cursor(right_win)[1] == 7
				and has_comment_keymap(new_buf)
		end, 20)

		package.loaded["codediff.ui.view"] = previous_view
		package.loaded["codediff.ui.lifecycle"] = previous_lifecycle
		assert.are.equal("/repo/b.lua", captured_cfg and captured_cfg.modified_path)
		assert.is_false(captured_auto_scroll)
		assert.is_true(ok, "expected Enter to focus the refreshed CodeDiff buffer with review keymaps attached")
	end)

	it("toggles open and close", function()
		local session = make_session()
		state.set_active(session)

		assert.is_false(thread_panel.is_open())
		thread_panel.toggle()
		assert.is_true(thread_panel.is_open())
		thread_panel.toggle()
		assert.is_false(thread_panel.is_open())
	end)

	it("updates the overview buffer when filters change", function()
		local session = make_session()
		state.set_active(session)
		thread_panel.open()

		session._thread_filter = { open = true, resolved = false, draft = false, stale = false }
		thread_panel.render(session)
		local rendered = text(vim.api.nvim_buf_get_lines(session.ui.thread_panel_buf, 0, -1, false))
		assert.matches("consider renaming", rendered)
		assert.not_matches("fixed this range", rendered)
		assert.not_matches("LGTM", rendered)

		session._thread_query = "range"
		thread_panel.render(session)
		rendered = text(vim.api.nvim_buf_get_lines(session.ui.thread_panel_buf, 0, -1, false))
		assert.matches("No threads match", rendered)
	end)
end)
