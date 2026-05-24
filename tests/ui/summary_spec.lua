local config = require("unified_review.config")
local manager = require("unified_review.session.manager")
local state = require("unified_review.session.state")
local summary = require("unified_review.ui.summary")

local function setup_config()
	local state_dir = vim.fn.tempname()
	vim.fn.mkdir(state_dir, "p")
	config.setup({ local_git = { state_dir = state_dir } })
	return state_dir
end

local function active_session()
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local session = {
		id = "summary-session",
		kind = "local_git",
		target = { root = root },
		files = { { path = "a.lua", hunks = {} } },
		selection = { file_index = 1 },
		threads = {},
	}
	state.set_active(session)
	return session
end

describe("review summary", function()
	after_each(function()
		config.setup({})
		state.clear_active()
		vim.g.unified_review_last_save = nil
		vim.g.unified_review_last_save_error = nil
	end)

	it("reports save failures without throwing when there is no active session", function()
		local result, err = summary.save_active(vim.fn.tempname(), "markdown")

		assert.is_nil(result)
		assert.are.equal("No active review session", err and err.message)
	end)

	it("saves the active review with machine-readable diagnostics", function()
		setup_config()
		active_session()
		local exported = assert(manager.create_comment("exported note", { kind = "file", path = "a.lua" }))
		local hidden = assert(manager.create_comment("hidden note", { kind = "file", path = "a.lua" }))
		assert(manager.toggle_thread_export(hidden.id))

		local path = vim.fn.tempname()
		local result, err = summary.save_active(path, "minimal")

		assert.is_nil(err)
		result = assert(result)
		assert.are.equal(path, result.path)
		assert.are.equal("minimal", result.format)
		assert.are.equal(2, result.thread_count)
		assert.are.equal(1, result.exported_thread_count)
		assert.is_false(result.empty)
		assert.is_true(result.bytes > 0)
		local saved = table.concat(vim.fn.readfile(path), "\n")
		assert.matches("a%.lua: exported note", saved)
		assert.not_matches("hidden note", saved)
		assert.is_true(exported.metadata.export)
	end)

	it("records the last command save result for external integrations", function()
		setup_config()
		active_session()
		assert(manager.create_comment("command save note", { kind = "file", path = "a.lua" }))

		local path = vim.fn.tempname()
		assert.is_true(summary.save(path, "minimal"))

		assert.are.equal(path, vim.g.unified_review_last_save.path)
		assert.are.equal(1, vim.g.unified_review_last_save.exported_thread_count)
		assert.are.equal(vim.NIL, vim.g.unified_review_last_save_error)
	end)
end)
