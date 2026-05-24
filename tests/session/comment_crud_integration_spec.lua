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

describe("comment CRUD integration", function()
	after_each(function()
		pcall(manager.close)
		state.clear_active()
		config.setup({})
		vim.cmd("silent! only")
	end)

	it("creates line, range, and file-level comments", function()
		setup_config()
		local repo = git_repo.changed_file()

		assert(manager.open_local({
			cwd = repo.root,
			base = repo.base,
			head = repo.head,
			range_kind = "two_dot",
		}))

		-- line comment
		local line_thread = assert(manager.create_comment("line note", {
			kind = "line",
			path = repo.path,
			side = "right",
			line = 2,
		}))
		assert.are.equal("open", line_thread.state)
		assert.are.equal("right", line_thread.target.side)
		assert.are.equal(2, line_thread.target.line)

		-- range comment
		local range_thread = assert(manager.create_comment("range note", {
			kind = "range",
			path = repo.path,
			start_line = 2,
			start_side = "right",
			line = 2,
			side = "right",
		}))
		assert.are.equal("range", range_thread.target.kind)

		-- file-level comment
		local file_thread = assert(manager.create_comment("file note", {
			kind = "file",
			path = repo.path,
		}))
		assert.are.equal("file", file_thread.target.kind)

		-- all three threads exist
		local all_threads = manager.list_threads()
		assert.are.equal(3, #all_threads)

		-- filter by path
		assert.are.equal(3, #manager.list_threads(repo.path))
		assert.are.equal(0, #manager.list_threads("nonexistent.lua"))
	end)

	it("edits drafts", function()
		setup_config()
		local repo = git_repo.changed_file()

		assert(manager.open_local({ cwd = repo.root, base = repo.base, head = repo.head, range_kind = "two_dot" }))
		local thread = assert(manager.create_comment("original", { kind = "file", path = repo.path }))
		local comment = thread.comments[1]

		assert(manager.edit_draft(comment.id, "edited body"))
		assert.are.equal("edited body", comment.body)
		assert.are.equal(1, #thread.comments)
	end)

	it("deletes individual drafts", function()
		setup_config()
		local repo = git_repo.changed_file()

		assert(manager.open_local({ cwd = repo.root, base = repo.base, head = repo.head, range_kind = "two_dot" }))
		local thread = assert(manager.create_comment("delete me", { kind = "file", path = repo.path }))
		local comment_id = thread.comments[1].id

		assert(manager.delete_draft(comment_id))
		-- thread removed because its only comment was deleted
		assert.are.equal(0, #manager.list_threads())
	end)

	it("resolves and reopens threads", function()
		setup_config()
		local repo = git_repo.changed_file()

		assert(manager.open_local({ cwd = repo.root, base = repo.base, head = repo.head, range_kind = "two_dot" }))
		local thread = assert(manager.create_comment("note", { kind = "file", path = repo.path }))

		assert(manager.resolve_thread(thread.id))
		assert.are.equal("resolved", thread.state)

		assert(manager.reopen_thread(thread.id))
		assert.are.equal("open", thread.state)
	end)

	it("clears all comments from a session", function()
		setup_config()
		local repo = git_repo.changed_file()

		assert(manager.open_local({ cwd = repo.root, base = repo.base, head = repo.head, range_kind = "two_dot" }))
		assert(manager.create_comment("one", { kind = "file", path = repo.path }))
		assert(manager.create_comment("two", { kind = "file", path = repo.path }))
		assert.are.equal(2, #manager.list_threads())

		assert(manager.clear_comments())
		assert.are.equal(0, #manager.list_threads())
	end)

	it("replies to existing threads", function()
		setup_config()
		local repo = git_repo.changed_file()

		assert(manager.open_local({ cwd = repo.root, base = repo.base, head = repo.head, range_kind = "two_dot" }))
		local thread = assert(manager.create_comment("initial", { kind = "file", path = repo.path }))

		local reply = assert(manager.reply(thread.id, "reply body"))
		assert.are.equal(thread.id, reply.thread_id)
		assert.are.equal(2, #thread.comments)
		assert.are.equal("reply body", thread.comments[2].body)
	end)

	it("persists and reloads the full thread graph", function()
		setup_config()
		local repo = git_repo.changed_file()

		local session = assert(manager.open_local({
			cwd = repo.root,
			base = repo.base,
			head = repo.head,
			range_kind = "two_dot",
		}))
		local thread = assert(manager.create_comment("persist", { kind = "file", path = repo.path }))
		assert(manager.reply(thread.id, "persist reply"))
		assert(manager.resolve_thread(thread.id))
		local session_id = session.id
		manager.close()

		local reopened = assert(manager.open_local({
			cwd = repo.root,
			base = repo.base,
			head = repo.head,
			range_kind = "two_dot",
		}))
		assert.are.equal(session_id, reopened.id)

		local threads = manager.list_threads(repo.path)
		assert.are.equal(1, #threads)
		local t = (threads or {})[1]
		if not t then
			return
		end
		assert.are.equal("resolved", t.state)
		assert.are.equal(2, #t.comments)
		local c1 = (t.comments or {})[1]
		local c2 = (t.comments or {})[2]
		if not c1 or not c2 then
			return
		end
		assert.are.equal("persist", c1.body)
		assert.are.equal("persist reply", c2.body)
	end)
end)
