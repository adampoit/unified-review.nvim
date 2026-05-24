local git_local = require("unified_review.providers.diff.git_local")
local git_repo = require("tests.helpers.git_repo")

describe("git local provider integration", function()
	it("opens a real temporary git repository diff", function()
		local repo = git_repo.changed_file()

		local session, err =
			git_local.open({ cwd = repo.root, base = repo.base, head = repo.head, range_kind = "two_dot" })

		assert.is_nil(err)
		assert.is_not_nil(session)
		session = assert(session)
		assert.are.equal("git_local", session.provider)
		assert.are.equal(vim.loop.fs_realpath(repo.root), vim.loop.fs_realpath(session.target.root))
		assert.are.equal(1, #session.files)
		assert.are.equal(repo.path, session.files[1].path)
		assert.is_true(#session.files[1].hunks > 0)
	end)
end)
