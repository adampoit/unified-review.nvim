local repo_store = require("unified_review.persist.repo_store")
local session_store = require("unified_review.persist.session_store")

describe("session persistence", function()
	it("computes stable repo ids", function()
		local id = repo_store.repo_id("/tmp/example-repo")
		assert.are.equal(id, repo_store.repo_id("/tmp/example-repo"))
		assert.matches("example%-repo%-", id)
	end)

	it("writes and reads versioned session data", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		local session = {
			id = "local:test",
			kind = "local_git",
			provider = "git_local",
			target = { root = root, base = "main", head = "HEAD" },
			threads = { { id = "thread-1", target = { kind = "file", path = "a.lua" }, comments = {} } },
		}

		local path = assert(session_store.write(session))
		assert.are.equal(1, vim.fn.filereadable(path))
		local data = assert(session_store.read(root, session.id))
		assert.are.equal(1, data.version)
		assert.are.equal("local:test", data.session.id)
		assert.are.equal("thread-1", data.threads[1].id)
	end)
end)
