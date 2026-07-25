local comment_editor = require("unified_review.ui.comment_editor")
local state = require("unified_review.session.state")

local function lua_string(value)
	return string.format("%q", value)
end

local function temp_session()
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local files_buf = vim.api.nvim_create_buf(false, true)
	local left_buf = vim.api.nvim_create_buf(false, true)
	local right_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "line 1", "line 2", "line 3" })
	local right_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(right_win, right_buf)
	return {
		id = "session-1",
		target = { root = root },
		selection = { file_index = 1 },
		files = { { path = "a.lua", status = "modified", hunks = {} } },
		threads = {},
		ui = {
			files_buffer = files_buf,
			left_buffer = left_buf,
			right_buffer = right_buf,
			right_window = right_win,
		},
	}
end

local function open_editor(opts)
	local editor = comment_editor.open(opts)
	assert(editor, "expected the inline comment editor to open")
	return editor
end

describe("comment editor", function()
	after_each(function()
		comment_editor.close()
		state.clear_active()
		vim.cmd("silent! only")
	end)

	it("saves a new comment from the scratch buffer", function()
		local session = temp_session()
		state.set_active(session)
		local editor = open_editor({ target = { kind = "file", path = "a.lua" } })
		vim.api.nvim_buf_set_lines(editor.buffer, 0, -1, false, { "hello", "world" })

		editor.save()

		assert.are.equal(1, #session.threads)
		assert.are.equal("hello\nworld", session.threads[1].comments[1].body)
	end)

	it("saves with :write", function()
		local session = temp_session()
		state.set_active(session)
		local editor = open_editor({ target = { kind = "file", path = "a.lua" } })
		vim.api.nvim_buf_set_lines(editor.buffer, 0, -1, false, { "written" })
		vim.api.nvim_set_current_buf(editor.buffer)

		vim.cmd.write()

		assert.are.equal(1, #session.threads)
		assert.are.equal("written", session.threads[1].comments[1].body)
	end)

	it("uses acwrite buffers so :w triggers BufWriteCmd", function()
		local session = temp_session()
		state.set_active(session)
		local editor = open_editor({ target = { kind = "file", path = "a.lua" } })

		assert.are.equal("acwrite", vim.bo[editor.buffer].buftype)
	end)

	it("does not switch buffers inside BufWriteCmd when saving with :wqa", function()
		local repo_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
		local temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")
		local child_script = temp_dir .. "/comment_editor_wqa.lua"
		vim.fn.writefile({
			"local root = " .. lua_string(repo_root),
			"vim.opt.runtimepath:prepend(root)",
			"package.path = root .. '/?.lua;' .. root .. '/?/init.lua;' .. package.path",
			"require('unified_review').setup({})",
			"local state = require('unified_review.session.state')",
			"local session_root = vim.fn.tempname()",
			"vim.fn.mkdir(session_root, 'p')",
			"local right_buf = vim.api.nvim_create_buf(false, true)",
			"vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { 'line 1' })",
			"local right_win = vim.api.nvim_get_current_win()",
			"vim.api.nvim_win_set_buf(right_win, right_buf)",
			"local session = { id = 'child-session', target = { root = session_root }, selection = { file_index = 1 }, files = { { path = 'a.lua', status = 'modified', hunks = {} } }, threads = {}, ui = { right_buffer = right_buf, right_window = right_win } }",
			"state.set_active(session)",
			"local editor = require('unified_review.ui.comment_editor').open({ target = { kind = 'file', path = 'a.lua' } })",
			"vim.api.nvim_buf_set_lines(editor.buffer, 0, -1, false, { 'save from wqa' })",
			"vim.bo[editor.buffer].modified = true",
			"vim.cmd('wqa')",
		}, child_script)

		local result = vim.system(
			{ vim.v.progpath, "--clean", "-n", "--headless", "-S", child_script },
			{ text = true }
		)
			:wait()

		assert.are.equal(0, result.code, result.stderr)
		assert.is_nil((result.stderr or ""):find("Entered other buffer unexpectedly", 1, true), result.stderr)
	end)

	it("focuses the editable popup window", function()
		local session = temp_session()
		state.set_active(session)
		local editor = open_editor({ target = { kind = "file", path = "a.lua" } })

		assert.are.equal(editor.buffer, vim.api.nvim_get_current_buf())
	end)

	it("leaves normal editing keys available in the editor", function()
		local session = temp_session()
		state.set_active(session)
		local editor = open_editor({ target = { kind = "file", path = "a.lua" } })
		local normal_maps = vim.api.nvim_buf_get_keymap(editor.buffer, "n")

		for _, map in ipairs(normal_maps) do
			assert.is_not_equal("s", map.lhs)
			assert.is_not_equal("a", map.lhs)
		end
	end)

	it("expands within a bounded inline editor while preserving wrap settings", function()
		local session = temp_session()
		state.set_active(session)
		local editor = open_editor({ target = { kind = "file", path = "a.lua" } })
		local win = vim.fn.bufwinid(editor.buffer)
		local initial_height = vim.api.nvim_win_get_height(win)

		assert.is_true(vim.wo[win].wrap)
		assert.is_true(vim.wo[win].linebreak)
		assert.is_false(vim.wo[win].scrollbind)
		assert.is_false(vim.wo[win].cursorbind)
		assert.is_false(vim.wo[win].diff)
		assert.is_true(initial_height > 1)

		vim.api.nvim_buf_set_lines(editor.buffer, 0, -1, false, {
			"one",
			"two",
			"three",
			"four",
			"five",
			"six",
			"seven",
			"eight",
			"nine",
			"ten",
			"eleven",
			"twelve",
			"thirteen",
			"fourteen",
		})
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = editor.buffer })
		vim.wait(100, function()
			return vim.api.nvim_win_get_height(win) > initial_height
		end)

		assert.is_true(vim.api.nvim_win_get_height(win) > initial_height)
		assert.is_true(vim.api.nvim_win_get_height(win) <= 10)
		assert.are.equal(14, vim.api.nvim_buf_line_count(editor.buffer))
	end)

	it("anchors the editor to reserved rows in the diff window", function()
		local session = temp_session()
		state.set_active(session)
		local editor = open_editor({ target = { kind = "line", path = "a.lua", side = "right", line = 2 } })
		local config = vim.api.nvim_win_get_config(editor.window)

		assert.are.equal("win", config.relative)
		assert.are.equal(session.ui.right_window, config.win)
		assert.are.same({ 1, 0 }, config.bufpos)
		assert.is_not_nil(session._inline_editor.geometry)
	end)

	it("cleans up reserved rows when the editor window is closed externally", function()
		local session = temp_session()
		state.set_active(session)
		local editor = open_editor({ target = { kind = "file", path = "a.lua" } })

		vim.api.nvim_win_close(editor.window, true)
		vim.wait(100, function()
			return session._inline_editor == nil
		end)

		assert.is_nil(session._inline_editor)
		assert.is_false(session._comment_editor_open)
	end)

	it("does not duplicate footer instructions in the editable buffer", function()
		local session = temp_session()
		state.set_active(session)
		local editor = open_editor({ target = { kind = "file", path = "a.lua" } })
		local lines = vim.api.nvim_buf_get_lines(editor.buffer, 0, -1, false)

		assert.are.same({ "" }, lines)
	end)

	it("cancels without creating a draft", function()
		local session = temp_session()
		state.set_active(session)
		local editor = open_editor({ target = { kind = "file", path = "a.lua" } })
		vim.api.nvim_buf_set_lines(editor.buffer, 0, -1, false, { "discard me" })

		editor.cancel()

		assert.are.equal(0, #session.threads)
	end)
end)
