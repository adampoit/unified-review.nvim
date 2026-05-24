local git = require("unified_review.integrations.git")
local git_repo = require("tests.helpers.git_repo")

local function run(root, args)
	local result = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
	assert.are.equal(0, result.code, result.stderr)
	return result.stdout or ""
end

describe("git integration", function()
	it("parses three-dot ranges", function()
		local base, head, range_kind = git.parse_range({ "origin/main...HEAD" })
		assert.are.equal("origin/main", base)
		assert.are.equal("HEAD", head)
		assert.are.equal("three_dot", range_kind)
	end)

	it("parses two-dot ranges", function()
		local base, head, range_kind = git.parse_range({ "origin/main..HEAD" })
		assert.are.equal("origin/main", base)
		assert.are.equal("HEAD", head)
		assert.are.equal("two_dot", range_kind)
	end)

	it("parses explicit base and head args", function()
		local base, head, range_kind = git.parse_range({ "main", "feature" })
		assert.are.equal("main", base)
		assert.are.equal("feature", head)
		assert.are.equal("three_dot", range_kind)
	end)

	it("renders range expressions", function()
		assert.are.equal("main...HEAD", git.range_expr("main", "HEAD", "three_dot"))
		assert.are.equal("main..HEAD", git.range_expr("main", "HEAD", "two_dot"))
	end)

	it("infers local master when configured origin/main does not exist", function()
		local root = git_repo.create()
		git_repo.write(root, "a.txt", { "one" })
		git_repo.commit(root, "initial")
		run(root, { "branch", "-m", "master" })

		assert.are.equal("master", git.infer_default_branch(root, "origin/main"))
	end)

	it("infers origin HEAD before common fallback names", function()
		local root = git_repo.create()
		git_repo.write(root, "a.txt", { "one" })
		git_repo.commit(root, "initial")
		run(root, { "branch", "-m", "trunk" })
		run(root, { "update-ref", "refs/remotes/origin/trunk", "HEAD" })
		run(root, { "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk" })

		assert.are.equal("origin/trunk", git.infer_default_branch(root, "origin/main"))
	end)

	it("resolves commit ranges from a Git directory without a worktree", function()
		local root = git_repo.create()
		git_repo.write(root, "a.txt", { "one" })
		git_repo.commit(root, "initial")
		git_repo.write(root, "a.txt", { "two" })
		git_repo.commit(root, "change")

		local resolved =
			assert(git.resolve_target({ base = "HEAD~1", head = "HEAD", range_kind = "two_dot" }, root .. "/.git"))
		local patch = git.patch(resolved.base_oid, resolved.head_oid, resolved.root, resolved.range_kind)

		assert.are.equal(root .. "/.git", resolved.root)
		assert.is_nil(resolved.worktree_root)
		assert.is_true(patch.ok, patch.stderr)
		assert.matches("two", patch.stdout)
	end)

	it("reports non-git directories", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")

		local root, err = git.repo_root(dir)
		assert.is_nil(root)
		assert.is_not_nil(err)
		assert.is_false(err.ok)
	end)
end)
