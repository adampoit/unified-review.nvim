local local_store = require("unified_review.providers.comments.local_store")

local function temp_session()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return {
		id = "session-1",
		kind = "local_git",
		provider = "git_local",
		target = { root = dir, base = "main", head = "HEAD" },
		threads = {},
	},
		dir
end

describe("local comment store", function()
	it("creates and lists local threads", function()
		local session = temp_session()
		local thread = assert(
			local_store.create_thread(session, { kind = "line", path = "a.lua", side = "right", line = 4 }, "note")
		)

		assert.are.equal("open", thread.state)
		assert.is_true(thread.metadata.export)
		assert.are.equal(1, #local_store.list_threads(session, "a.lua"))
		assert.are.equal(0, #local_store.list_threads(session, "b.lua"))
	end)

	it("adds replies to existing threads", function()
		local session = temp_session()
		local thread = assert(local_store.create_thread(session, { kind = "file", path = "a.lua" }, "note"))
		local reply = assert(local_store.reply(session, thread.id, "reply"))

		assert.are.equal(thread.id, reply.thread_id)
		assert.are.equal(2, #thread.comments)
	end)

	it("persists and reloads threads", function()
		local session, dir = temp_session()
		assert(local_store.create_thread(session, { kind = "line", path = "a.lua", side = "right", line = 4 }, "note"))

		local reloaded = { id = session.id, target = { root = dir } }
		assert(local_store.load(reloaded))
		assert.are.equal(1, #reloaded.threads)
		assert.are.equal("note", reloaded.threads[1].comments[1].body)
		assert.is_true(reloaded.threads[1].metadata.export)
	end)

	it("stores a file content id for exact reload matches", function()
		local session, dir = temp_session()
		vim.fn.writefile({ "one", "selected", "three" }, dir .. "/a.lua")
		local thread = assert(
			local_store.create_thread(session, { kind = "line", path = "a.lua", side = "right", line = 2 }, "note")
		)

		assert.is_string(thread.metadata.anchor.file_content_id)
	end)

	it("remaps anchored threads when files move after reload", function()
		local session, dir = temp_session()
		vim.fn.writefile({ "one", "selected", "three" }, dir .. "/a.lua")
		assert(local_store.create_thread(session, { kind = "line", path = "a.lua", side = "right", line = 2 }, "note"))
		vim.fn.writefile({ "inserted", "one", "selected", "three" }, dir .. "/a.lua")

		local reloaded = { id = session.id, target = { root = dir } }
		assert(local_store.load(reloaded))
		assert.are.equal(3, reloaded.threads[1].target.line)
	end)

	it("uses context to remap changed selected text", function()
		local session, dir = temp_session()
		vim.fn.writefile({ "before", "old selected", "after" }, dir .. "/a.lua")
		assert(local_store.create_thread(session, { kind = "line", path = "a.lua", side = "right", line = 2 }, "note"))
		vim.fn.writefile({ "top", "before", "new selected", "after" }, dir .. "/a.lua")

		local reloaded = { id = session.id, target = { root = dir } }
		assert(local_store.load(reloaded))
		assert.are.equal(3, reloaded.threads[1].target.line)
		assert.is_false(reloaded.threads[1].is_outdated)
	end)

	it("marks ambiguous remaps stale", function()
		local session, dir = temp_session()
		vim.fn.writefile({ "selected" }, dir .. "/a.lua")
		assert(local_store.create_thread(session, { kind = "line", path = "a.lua", side = "right", line = 1 }, "note"))
		vim.fn.writefile({ "other", "selected", "selected" }, dir .. "/a.lua")

		local reloaded = { id = session.id, target = { root = dir } }
		assert(local_store.load(reloaded))
		assert.are.equal("stale", reloaded.threads[1].state)
		assert.is_true(reloaded.threads[1].is_outdated)
	end)

	it("marks missing files stale", function()
		local session, dir = temp_session()
		vim.fn.writefile({ "selected" }, dir .. "/a.lua")
		assert(local_store.create_thread(session, { kind = "line", path = "a.lua", side = "right", line = 1 }, "note"))
		vim.fn.delete(dir .. "/a.lua")

		local reloaded = { id = session.id, target = { root = dir } }
		assert(local_store.load(reloaded))
		assert.are.equal("stale", reloaded.threads[1].state)
		assert.is_true(reloaded.threads[1].is_outdated)
	end)

	it("edits and deletes drafts", function()
		local session = temp_session()
		local thread = assert(local_store.create_thread(session, { kind = "file", path = "a.lua" }, "note"))
		local comment = thread.comments[1]

		assert(local_store.edit_draft(session, comment.id, "edited"))
		assert.are.equal("edited", thread.comments[1].body)

		assert(local_store.delete_draft(session, comment.id))
		assert.are.equal(0, #thread.comments)
		assert.are.equal(0, #session.threads)
	end)
end)
