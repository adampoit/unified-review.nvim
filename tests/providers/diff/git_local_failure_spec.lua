local git_local = require("unified_review.providers.diff.git_local")
local git_repo = require("tests.helpers.git_repo")

local function run(root, args)
	local result = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
	assert.are.equal(0, result.code, result.stderr)
	return result.stdout or ""
end

describe("git local diff provider failures", function()
	it("returns an error for non-git directories", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")

		local session, err = git_local.open({ cwd = dir, base = "main", head = "HEAD" })

		assert.is_nil(session)
		assert.is_not_nil(err)
		assert.is_false(assert(err).ok)
	end)

	it("returns an error for invalid refs", function()
		local repo = git_repo.changed_file()

		local session, err = git_local.open({
			cwd = repo.root,
			base = "does-not-exist",
			head = repo.head,
			range_kind = "two_dot",
		})

		assert.is_nil(session)
		assert.is_not_nil(err)
		assert.is_false(assert(err).ok)
	end)

	it("opens without args using inferred default branch when origin/main is missing", function()
		local repo = git_repo.changed_file()
		run(repo.root, { "branch", "-m", "feature" })
		run(repo.root, { "branch", "master", repo.base })

		local session, err = git_local.open({ cwd = repo.root })

		assert.is_nil(err)
		assert.is_not_nil(session)
		local opened = assert(session)
		assert.are.equal("master", opened.target.base)
		assert.are.equal(1, #opened.files)
	end)

	it("opens empty diffs as sessions with no files", function()
		local repo = git_repo.changed_file()

		local session, err =
			git_local.open({ cwd = repo.root, base = repo.head, head = repo.head, range_kind = "two_dot" })

		assert.is_nil(err)
		assert.is_not_nil(session)
		local opened = assert(session)
		assert.are.equal(0, #opened.files)
		assert.are.equal("", opened.raw_patch)
	end)
end)
