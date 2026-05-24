local config = require("unified_review.config")
local manager = require("unified_review.session.manager")
local state = require("unified_review.session.state")
local git_repo = require("tests.helpers.git_repo")

local function setup_config()
	local state_dir = vim.fn.tempname()
	vim.fn.mkdir(state_dir, "p")
	config.setup({ local_git = { state_dir = state_dir } })
	return state_dir
end

describe("session manager git integration", function()
	after_each(function()
		pcall(manager.close)
		state.clear_active()
		config.setup({})
		vim.cmd("silent! only")
	end)

	it("opens a real local git review session", function()
		setup_config()
		local repo = git_repo.changed_file()

		local session, err =
			manager.open_local({ cwd = repo.root, base = repo.base, head = repo.head, range_kind = "two_dot" })

		assert.is_nil(err)
		assert.is_not_nil(session)
		session = assert(session)
		assert.are.equal(session, manager.active())
		assert.are.equal("local_git", session.kind)
		assert.are.equal(1, #session.files)
		assert.are.equal("a.lua", session.files[1].path)
	end)

	it("persists comments across closing and reopening a real local git review", function()
		setup_config()
		local repo = git_repo.changed_file()

		local first =
			assert(manager.open_local({ cwd = repo.root, base = repo.base, head = repo.head, range_kind = "two_dot" }))
		assert(manager.create_comment("persist me", { kind = "file", path = repo.path }))
		local session_id = first.id
		manager.close()

		local reopened =
			assert(manager.open_local({ cwd = repo.root, base = repo.base, head = repo.head, range_kind = "two_dot" }))

		assert.are.equal(session_id, reopened.id)
		assert.are.equal(1, #manager.list_threads(repo.path))
		assert.are.equal("persist me", manager.list_threads(repo.path)[1].comments[1].body)
	end)
end)
