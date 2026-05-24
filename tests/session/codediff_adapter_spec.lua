local diff_view = require("unified_review.ui.diff_view")
local signs = require("unified_review.ui.signs")
local selection = require("unified_review.session.selection")
local config = require("unified_review.config")
local state = require("unified_review.session.state")

local function has_codediff()
	local ok, _ = pcall(require, "codediff.ui.lifecycle")
	-- also require the view module
	local ok_view, _ = pcall(require, "codediff.ui.view")
	return ok and ok_view
end

describe("codediff adapter", function()
	before_each(function()
		config.setup({})
	end)

	after_each(function()
		state.clear_active()
		config.setup({})
		vim.cmd("silent! only")
	end)

	it("sync_from_codediff captures buffer and window handles", function()
		if not has_codediff() then
			pending("codediff.nvim is not available")
			return
		end

		-- create buffers to simulate CodeDiff output
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, { "line 1", "line 2", "line 3" })
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "line 1", "changed 2", "line 3" })

		-- simulate CodeDiff windows
		vim.cmd("vsplit")
		local right_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(right_win, right_buf)
		local left_win = vim.api.nvim_open_win(left_buf, false, {
			relative = "win",
			win = right_win,
			width = math.floor(vim.o.columns / 2),
			height = vim.o.lines,
			row = 0,
			col = 0,
		})

		local session = {
			id = "codediff-test-1",
			target = { root = "/tmp/test" },
			files = { { path = "a.lua", old_path = "a.lua", status = "modified", hunks = {} } },
			selection = { file_index = 1, hunk_index = 1 },
			threads = {},
			ui = { left_buffer = left_buf, right_buffer = right_buf },
		}
		state.set_active(session)

		diff_view._attach_review_keymaps(session)
		signs.place(session)

		-- verify keymaps were installed (at least one normal-mode mapping exists)
		local maps = vim.api.nvim_buf_get_keymap(right_buf, "n")
		assert.is_true(#maps > 0, "expected keymaps on right buffer")

		signs.clear(session)
		pcall(vim.api.nvim_win_close, left_win, true)
		pcall(vim.api.nvim_win_close, right_win, true)
	end)

	it("attaches review keymaps to the codediff explorer buffer", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		local right_buf = vim.api.nvim_create_buf(false, true)
		local explorer_buf = vim.api.nvim_create_buf(false, true)
		local session = {
			ui = {
				left_buffer = left_buf,
				right_buffer = right_buf,
				codediff_session = { explorer = { bufnr = explorer_buf } },
			},
		}

		diff_view._attach_review_keymaps(session)

		local maps = vim.api.nvim_buf_get_keymap(explorer_buf, "n")
		local found = false
		for _, map in ipairs(maps) do
			if map.rhs == "<Cmd>UnifiedReview comment<CR>" then
				found = true
				break
			end
		end
		assert.is_true(found, "expected review comment keymap on explorer buffer")
	end)

	it("renders current-code Git targets with a working-copy right side", function()
		local previous_view = package.loaded["codediff.ui.view"]
		local previous_lifecycle = package.loaded["codediff.ui.lifecycle"]
		local left_buf = vim.api.nvim_create_buf(false, true)
		local right_buf = vim.api.nvim_create_buf(false, true)
		local captured
		package.loaded["codediff.ui.view"] = {
			create = function(cfg)
				captured = vim.deepcopy(cfg)
				return { original_buf = left_buf, modified_buf = right_buf }
			end,
		}
		package.loaded["codediff.ui.lifecycle"] = {
			get_buffers = function()
				return left_buf, right_buf
			end,
			get_windows = function()
				return nil, nil
			end,
			get_paths = function()
				return "a.lua", "a.lua"
			end,
			get_session = function()
				return {}
			end,
		}

		diff_view.render({
			id = "git-current-code",
			target = { root = "/repo", worktree_root = "/repo", base_oid = "base", head_oid = "WORKING" },
			files = { { path = "a.lua", status = "modified", hunks = {} } },
			selection = { file_index = 1 },
			threads = {},
		})

		package.loaded["codediff.ui.view"] = previous_view
		package.loaded["codediff.ui.lifecycle"] = previous_lifecycle
		assert.are.equal("/repo", captured.git_root)
		assert.are.equal("WORKING", captured.modified_revision)
	end)

	it("renders current jj changes with the workspace root instead of the .git directory", function()
		local previous_view = package.loaded["codediff.ui.view"]
		local previous_lifecycle = package.loaded["codediff.ui.lifecycle"]
		local left_buf = vim.api.nvim_create_buf(false, true)
		local right_buf = vim.api.nvim_create_buf(false, true)
		local captured
		package.loaded["codediff.ui.view"] = {
			create = function(cfg)
				captured = vim.deepcopy(cfg)
				return { original_buf = left_buf, modified_buf = right_buf }
			end,
		}
		package.loaded["codediff.ui.lifecycle"] = {
			get_buffers = function()
				return left_buf, right_buf
			end,
			get_windows = function()
				return nil, nil
			end,
			get_paths = function()
				return "a.lua", "a.lua"
			end,
			get_session = function()
				return {}
			end,
		}

		diff_view.render({
			id = "jj-current-code",
			target = {
				kind = "jj",
				root = "/repo",
				git_root = "/repo/.git",
				base_oid = "base",
				head_oid = "head",
				head_revset = "@",
			},
			files = { { path = "a.lua", status = "modified", hunks = {} } },
			selection = { file_index = 1 },
			threads = {},
		})

		package.loaded["codediff.ui.view"] = previous_view
		package.loaded["codediff.ui.lifecycle"] = previous_lifecycle
		assert.are.equal("/repo", captured.git_root)
		assert.are.equal("WORKING", captured.modified_revision)
	end)

	it("attaches review keymaps after a one-sided file selection replaces the diff buffer", function()
		local previous_view = package.loaded["codediff.ui.view"]
		local previous_lifecycle = package.loaded["codediff.ui.lifecycle"]
		local tabpage = vim.api.nvim_get_current_tabpage()
		local win = vim.api.nvim_get_current_win()
		local old_buf = vim.api.nvim_create_buf(false, true)
		local new_buf = vim.api.nvim_create_buf(false, true)
		local empty_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(win, old_buf)

		local lifecycle_state = {
			left_buf = old_buf,
			right_buf = old_buf,
			left_win = win,
			right_win = win,
			original_path = "old.lua",
			modified_path = "old.lua",
			session = {},
		}
		package.loaded["codediff.ui.view"] = {}
		package.loaded["codediff.ui.lifecycle"] = {
			get_buffers = function()
				return lifecycle_state.left_buf, lifecycle_state.right_buf
			end,
			get_windows = function()
				return lifecycle_state.left_win, lifecycle_state.right_win
			end,
			get_session = function()
				return lifecycle_state.session
			end,
			get_paths = function()
				return lifecycle_state.original_path, lifecycle_state.modified_path
			end,
		}

		local session = {
			id = "codediff-one-sided-keymaps",
			target = { root = "/repo" },
			files = { { path = "added.lua", status = "added", hunks = {} } },
			selection = { file_index = 1, hunk_index = 1 },
			threads = {},
			ui = {},
		}

		diff_view.attach(session, tabpage)
		vim.api.nvim_exec_autocmds("User", {
			pattern = "CodeDiffFileSelect",
			modeline = false,
			data = { tabpage = tabpage, path = "added.lua", status = "A" },
		})

		lifecycle_state.left_buf = empty_buf
		lifecycle_state.right_buf = new_buf
		lifecycle_state.left_win = nil
		lifecycle_state.right_win = win
		lifecycle_state.original_path = ""
		lifecycle_state.modified_path = "/repo/added.lua"
		vim.api.nvim_win_set_buf(win, new_buf)

		local ok = vim.wait(500, function()
			for _, map in ipairs(vim.api.nvim_buf_get_keymap(new_buf, "n")) do
				if map.rhs == "<Cmd>UnifiedReview comment<CR>" then
					return true
				end
			end
			return false
		end, 20)

		package.loaded["codediff.ui.view"] = previous_view
		package.loaded["codediff.ui.lifecycle"] = previous_lifecycle
		assert.is_true(ok, "expected review comment keymap on the replacement added-file buffer")
	end)

	it("places signs at correct lines for a given session", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, { "left 1", "left 2", "left 3", "left 4" })
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "line one", "line two", "line three", "line four" })

		local session = {
			id = "sign-test-1",
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			files = {
				{
					path = "a.lua",
					hunks = {
						{
							header = "@@ -1,4 +1,4 @@",
							old_start = 1,
							new_start = 1,
							lines = {
								{ kind = "context", old_line = 1, new_line = 1 },
								{ kind = "added", new_line = 2, text = "line two" },
								{ kind = "context", old_line = 2, new_line = 3 },
								{ kind = "deleted", old_line = 3, text = "line three" },
							},
						},
					},
				},
			},
			selection = { file_index = 1, hunk_index = 1 },
			threads = {
				{
					id = "thread-1",
					state = "open",
					target = { kind = "line", path = "a.lua", side = "right", line = 2 },
					comments = { { state = "draft", body = "check this" } },
				},
				{
					id = "thread-2",
					state = "resolved",
					target = { kind = "line", path = "a.lua", side = "left", line = 3 },
					comments = { { state = "open", body = "fixed" } },
				},
			},
		}

		signs.place(session)

		-- right buffer should have thread-1 signs at line 2
		local right_signs = vim.fn.sign_getplaced(right_buf, { group = "unified_review_threads" })[1].signs
		assert.are.equal(2, #right_signs, "expected thread and export signs on right buffer")
		local right_by_name = {}
		for _, sign in ipairs(right_signs) do
			right_by_name[sign.name] = sign
		end
		assert.are.equal(2, right_by_name.UnifiedReviewDraft.lnum)
		assert.are.equal(2, right_by_name.UnifiedReviewExported.lnum)

		-- left buffer should have thread-2 sign at line 3
		local left_signs = vim.fn.sign_getplaced(left_buf, { group = "unified_review_threads" })[1].signs
		assert.are.equal(1, #left_signs, "expected 1 sign on left buffer")
		assert.are.equal(3, left_signs[1].lnum)
		assert.are.equal("UnifiedReviewResolved", left_signs[1].name)

		signs.clear(session)
		right_signs = vim.fn.sign_getplaced(right_buf, { group = "unified_review_threads" })[1].signs
		assert.are.equal(0, #right_signs)
		left_signs = vim.fn.sign_getplaced(left_buf, { group = "unified_review_threads" })[1].signs
		assert.are.equal(0, #left_signs)
	end)

	it("detects comment targets after simulated buffer content change", function()
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "line 1", "line 2", "line 3" })

		-- open a window so current_target can read cursor position
		local right_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(right_win, right_buf)
		vim.api.nvim_win_set_cursor(right_win, { 2, 0 })

		local session = {
			ui = {
				left_buffer = vim.api.nvim_create_buf(false, true),
				right_buffer = right_buf,
				right_window = right_win,
			},
			files = { { path = "a.lua", status = "modified", hunks = {} } },
			selection = { file_index = 1, hunk_index = 1 },
			threads = {},
		}

		local target = selection.current_target(session)
		assert.is_not_nil(target)
		if not target then
			return
		end
		assert.are.equal("line", target.kind)
		assert.are.equal("right", target.side)
		assert.are.equal(2, target.line)
		assert.are.equal("a.lua", target.path)
	end)

	it("focuses hunks via parsed diff data when no codediff session", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, { "a1", "a2", "a3", "a4" })
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "b1", "b2", "b3", "b4" })

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
			selection = { file_index = 1, hunk_index = 3 },
			files = {
				{
					path = "a.lua",
					hunks = {
						{ header = "@@ -1 +1 @@", old_start = 1, new_start = 1, lines = {} },
						{ header = "@@ -2 +2 @@", old_start = 2, new_start = 2, lines = {} },
						{ header = "@@ -4 +4 @@", old_start = 4, new_start = 4, lines = {} },
					},
				},
			},
		}

		-- focus from right window
		vim.api.nvim_set_current_win(right_win)
		diff_view.focus_hunk(session)
		assert.are.equal(4, vim.api.nvim_win_get_cursor(right_win)[1])
	end)
end)
