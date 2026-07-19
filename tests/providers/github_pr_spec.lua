local provider = require("unified_review.providers.diff.github_pr")
local diff_builder = require("helpers.diff_builder")
local git_repo = require("helpers.git_repo")
local jj_repo = require("helpers.jj_repo")

local patch = diff_builder.diff({
	diff_builder.file("src/right-longer-replacement.txt", {
		diff_builder.ctx("before", 2),
		diff_builder.del("old", 1),
		diff_builder.add("new", 3),
		diff_builder.ctx("after", 2),
	}),
}).patch

describe("GitHub PR diff provider", function()
	it("loads PR metadata and parses patch files with GitHub positions", function()
		local gh = require("unified_review.integrations.gh")
		local original_available = gh.available
		local original_pr_view = gh.pr_view
		local original_pr_diff = gh.pr_diff
		local ok, err = pcall(function()
			rawset(gh, "available", function()
				return true
			end)
			rawset(gh, "pr_view", function()
				return {
					id = "PR_kw123",
					owner = "acme",
					repo = "widgets",
					number = 42,
					url = "https://github.com/acme/widgets/pull/42",
					title = "Add widgets",
					base_ref = "main",
					head_ref = "feature",
					base_ref_oid = "baseoid",
					head_ref_oid = "headoid",
				},
					nil
			end)
			rawset(gh, "pr_diff", function()
				return patch, nil
			end)

			local session = assert(provider.open({ kind = "github_pr", number = 42, cwd = "/repo" }))

			assert.are.equal("github_pr", session.provider)
			assert.is_false(session.editable)
			assert.are.equal("acme", session.target.owner)
			assert.are.equal("widgets", session.target.repo)
			assert.are.equal("PR_kw123", session.target.pull_request_id)
			assert.are.equal(1, #session.files)
			assert.are.equal("src/right-longer-replacement.txt", session.files[1].path)
			assert.are.equal(4, session.files[1].hunks[1].lines[3].metadata.github.position)
			assert.are.equal("LEFT", session.files[1].hunks[1].lines[3].metadata.github.side)
		end)
		gh.available = original_available
		gh.pr_view = original_pr_view
		gh.pr_diff = original_pr_diff
		if not ok then
			error(err)
		end
	end)

	it("renders GitHub PR comments against the local worktree when requested", function()
		local gh = require("unified_review.integrations.gh")
		local original_available = gh.available
		local original_pr_view = gh.pr_view
		local original_pr_diff = gh.pr_diff
		local root = git_repo.create()
		git_repo.write(root, "a.lua", { "return 1" })
		git_repo.commit(root, "base")
		vim.fn.system({ "git", "-C", root, "update-ref", "refs/remotes/origin/main", "HEAD" })
		git_repo.write(root, "a.lua", { "return 2" })
		local remote_patch = diff_builder.diff({
			diff_builder.file("a.lua", {
				diff_builder.del("return 1", 1),
				diff_builder.add("return 2", 1),
			}),
		}).patch
		local ok, err = pcall(function()
			rawset(gh, "available", function()
				return true
			end)
			rawset(gh, "pr_view", function()
				return {
					id = "PR_kw123",
					owner = "acme",
					repo = "widgets",
					number = 42,
					url = "https://github.com/acme/widgets/pull/42",
					title = "Add widgets",
					base_ref = "main",
					head_ref = "feature",
					base_ref_oid = "baseoid",
					head_ref_oid = "headoid",
				},
					nil
			end)
			rawset(gh, "pr_diff", function()
				return remote_patch, nil
			end)

			local session = assert(
				provider.open({ kind = "github_pr", number = 42, cwd = root, render_strategy = "local_worktree" })
			)

			assert.are.equal("github_pr", session.provider)
			assert.are.equal("github-local:acme:widgets:42", session.id)
			assert.is_true(session.editable)
			assert.is_false(session.read_only)
			assert.are.equal(
				vim.loop.fs_realpath(root) or root,
				vim.loop.fs_realpath(session.target.root) or session.target.root
			)
			assert.are.equal("local_worktree", session.target.render_strategy)
			assert.are.equal("WORKING", session.target.head_oid)
			assert.are.equal("WORKING", session.target.render_head_oid)
			assert.are.equal(1, #session.files)
			assert.are.equal("a.lua", session.files[1].path)
			assert.are.equal("return 2", session.files[1].hunks[1].lines[2].text)
			assert.are.equal(1, #session.metadata.github_remote_files)
		end)
		gh.available = original_available
		gh.pr_view = original_pr_view
		gh.pr_diff = original_pr_diff
		if not ok then
			error(err)
		end
	end)

	it("resolves GitHub and local review context from an additional jj workspace", function()
		local gh = require("unified_review.integrations.gh")
		local original_available = gh.available
		local original_pr_view = gh.pr_view
		local original_pr_diff = gh.pr_diff
		local root = jj_repo.create()
		jj_repo.write(root, "a.lua", { "return 1" })
		jj_repo.describe(root, "base")
		jj_repo.remote_bookmark(root, "main", "@")
		local workspace = jj_repo.add_workspace(root)
		jj_repo.write(workspace, "a.lua", { "return 2" })
		jj_repo.describe(workspace, "workspace change")
		local git_root = jj_repo.run(workspace, { "git", "root" }):gsub("%s+$", "")
		local remote_patch = diff_builder.diff({
			diff_builder.file("a.lua", {
				diff_builder.del("return 1", 1),
				diff_builder.add("return 2", 1),
			}),
		}).patch
		local requested_cwds = {}
		local ok, err = pcall(function()
			rawset(gh, "available", function()
				return true
			end)
			rawset(gh, "pr_view", function(cwd)
				table.insert(requested_cwds, cwd)
				return {
					id = "PR_kw123",
					owner = "acme",
					repo = "widgets",
					number = 42,
					url = "https://github.com/acme/widgets/pull/42",
					title = "Add widgets",
					base_ref = "main",
					head_ref = "feature",
					base_ref_oid = "baseoid",
					head_ref_oid = "headoid",
				},
					nil
			end)
			rawset(gh, "pr_diff", function(cwd)
				table.insert(requested_cwds, cwd)
				return remote_patch, nil
			end)

			local session = assert(provider.open({
				kind = "github_pr",
				number = 42,
				cwd = workspace,
				render_strategy = "local_worktree",
			}))

			assert.is_nil(vim.loop.fs_stat(workspace .. "/.git"))
			assert.are.equal(vim.loop.fs_realpath(git_root), vim.loop.fs_realpath(requested_cwds[1]))
			assert.are.equal(vim.loop.fs_realpath(git_root), vim.loop.fs_realpath(requested_cwds[2]))
			assert.are.equal(vim.loop.fs_realpath(workspace), vim.loop.fs_realpath(session.target.root))
			assert.are.equal("jj", session.target.local_provider)
			assert.are.equal("return 2", session.files[1].hunks[1].lines[2].text)
		end)
		gh.available = original_available
		gh.pr_view = original_pr_view
		gh.pr_diff = original_pr_diff
		if not ok then
			error(err)
		end
	end)

	it("renders GitHub PR comments against a jj local worktree when requested", function()
		local gh = require("unified_review.integrations.gh")
		local original_available = gh.available
		local original_pr_view = gh.pr_view
		local original_pr_diff = gh.pr_diff
		local previous_jj_provider = package.loaded["unified_review.providers.diff.jj_local"]
		local captured_target
		local ok, err = pcall(function()
			rawset(gh, "available", function()
				return true
			end)
			rawset(gh, "pr_view", function()
				return {
					id = "PR_kw123",
					owner = "acme",
					repo = "widgets",
					number = 42,
					url = "https://github.com/acme/widgets/pull/42",
					title = "Add widgets",
					base_ref = "main",
					head_ref = "feature",
					base_ref_oid = "baseoid",
					head_ref_oid = "headoid",
				},
					nil
			end)
			rawset(gh, "pr_diff", function()
				return patch, nil
			end)
			package.loaded["unified_review.providers.diff.jj_local"] = {
				open = function(target)
					captured_target = vim.deepcopy(target)
					return {
						target = {
							root = "/workspace",
							git_root = "/workspace/.jj/repo/store/git",
							base = target.base,
							head = target.head,
							base_oid = "mergebase",
							head_oid = "working-copy-oid",
						},
						files = { { path = "a.lua", hunks = {} } },
						raw_patch = "diff --git a/a.lua b/a.lua\n",
					},
						nil
				end,
			}

			local session = assert(provider.open({
				kind = "github_pr",
				number = 42,
				cwd = "/workspace/.jj/repo/store/git",
				render_strategy = "local_worktree",
				local_provider = "jj",
				local_root = "/workspace",
				local_base = "main@origin",
				git_root = "/workspace/.jj/repo/store/git",
			}))

			assert.are.equal("/workspace", captured_target.root)
			assert.are.equal("main@origin", captured_target.base)
			assert.are.equal("@", captured_target.head)
			assert.are.equal("three_dot", captured_target.range_kind)
			assert.are.equal("github_pr", session.provider)
			assert.are.equal("local_worktree", session.target.render_strategy)
			assert.are.equal("/workspace", session.target.root)
			assert.are.equal("working-copy-oid", session.target.head_oid)
			assert.are.equal("WORKING", session.target.render_head_oid)
			assert.is_true(session.editable)
			assert.is_false(session.read_only)
			assert.are.equal(1, #session.metadata.github_remote_files)
		end)
		gh.available = original_available
		gh.pr_view = original_pr_view
		gh.pr_diff = original_pr_diff
		package.loaded["unified_review.providers.diff.jj_local"] = previous_jj_provider
		if not ok then
			error(err)
		end
	end)

	it("resolves the current branch PR when no PR ref is provided", function()
		local gh = require("unified_review.integrations.gh")
		local original_available = gh.available
		local original_resolve = gh.resolve_pr_from_branch_context
		local original_pr_view = gh.pr_view
		local original_pr_diff = gh.pr_diff
		local resolved_ref
		local ok, err = pcall(function()
			rawset(gh, "available", function()
				return true
			end)
			rawset(gh, "resolve_pr_from_branch_context", function(cwd)
				assert.are.equal("/repo", cwd)
				return { number = 42 }, nil
			end)
			rawset(gh, "pr_view", function(_, ref)
				resolved_ref = ref
				return {
					id = "PR_kw123",
					owner = "acme",
					repo = "widgets",
					number = 42,
					url = "https://github.com/acme/widgets/pull/42",
					title = "Add widgets",
					base_ref = "main",
					head_ref = "feature",
					base_ref_oid = "baseoid",
					head_ref_oid = "headoid",
				},
					nil
			end)
			rawset(gh, "pr_diff", function()
				return patch, nil
			end)

			local session = assert(provider.open({ kind = "github_pr", cwd = "/repo" }))

			assert.are.equal(42, resolved_ref)
			assert.are.equal("github_pr", session.provider)
		end)
		gh.available = original_available
		gh.resolve_pr_from_branch_context = original_resolve
		gh.pr_view = original_pr_view
		gh.pr_diff = original_pr_diff
		if not ok then
			error(err)
		end
	end)
end)
