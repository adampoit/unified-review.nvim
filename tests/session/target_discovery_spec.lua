local config = require("unified_review.config")
local discovery = require("unified_review.session.target_discovery")
local git_repo = require("tests.helpers.git_repo")
local jj_repo = require("tests.helpers.jj_repo")

local function run(root, args)
	local result = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
	if result.code ~= 0 then
		error((result.stderr or "git failed") .. "\n" .. table.concat(args, " "))
	end
	return result.stdout or ""
end

local function by_id(items)
	local result = {}
	for _, item in ipairs(items or {}) do
		result[item.id] = item
	end
	return result
end

local function item_index(items, id)
	for index, item in ipairs(items or {}) do
		if item.id == id then
			return index
		end
	end
	return nil
end

local function git_head_contents(root)
	local path = (jj_repo.run_git(root, { "rev-parse", "--git-path", "HEAD" }) or ""):gsub("%s+$", "")
	if not vim.startswith(path, "/") then
		path = root .. "/" .. path
	end
	return table.concat(vim.fn.readfile(path), "\n")
end

describe("target discovery", function()
	after_each(function()
		package.loaded["unified_review.integrations.gh"] = nil
		config.setup({})
	end)

	it("builds Git picker targets with current-code and meta options", function()
		local root = git_repo.create()
		git_repo.write(root, "a.lua", { "return 1" })
		git_repo.commit(root, "base")
		run(root, { "update-ref", "refs/remotes/origin/main", "HEAD" })
		git_repo.write(root, "a.lua", { "return 2" })
		git_repo.commit(root, "change")
		git_repo.write(root, "a.lua", { "return 3" })

		local result = assert(discovery.discover({ cwd = root, prefer_jj = false }))
		local items = by_id(result.items)

		assert.are.equal("git", result.mode)
		assert.is_not_nil(items["git-working"])
		assert.is_not_nil(items["git-origin/main"])
		assert.is_not_nil(items["git-origin/main-two-dot"])
		assert.is_not_nil(items["git-last-commit"])
		assert.is_not_nil(items["github-pr-picker"])
		assert.are.equal("github_pr_picker", items["github-pr-picker"].kind)
		assert.is_not_nil(items["commit-range"])
		assert.is_false(items["commit-range"].disabled)
		assert.are.same({}, items["commit-range"].warnings)
		assert.is_not_nil(items.custom)
		assert.are.equal("WORKING", items["git-origin/main"].target.head)
		assert.are.equal("working_tree_three_dot", items["git-origin/main"].target.range_kind)
		assert.are.equal("WORKING", items["git-origin/main-two-dot"].target.head)
		assert.are.equal("working_tree", items["git-origin/main-two-dot"].target.range_kind)
	end)

	it("uses the working copy for current-code Git targets even when clean", function()
		local root = git_repo.create()
		git_repo.write(root, "a.lua", { "return 1" })
		git_repo.commit(root, "base")
		run(root, { "update-ref", "refs/remotes/origin/main", "HEAD" })
		git_repo.write(root, "a.lua", { "return 2" })
		git_repo.commit(root, "change")

		local result = assert(discovery.discover({ cwd = root, prefer_jj = false }))
		local items = by_id(result.items)

		assert.is_nil(items["git-working"])
		assert.are.equal("WORKING", items["git-origin/main"].target.head)
		assert.are.equal("working_tree_three_dot", items["git-origin/main"].target.range_kind)
		assert.are.equal("WORKING", items["git-origin/main-two-dot"].target.head)
		assert.are.equal("working_tree", items["git-origin/main-two-dot"].target.range_kind)
	end)

	it("adds only an inferred GitHub PR target next to the PR picker", function()
		local root = git_repo.create()
		git_repo.write(root, "a.lua", { "return 1" })
		git_repo.commit(root, "base")
		run(root, { "update-ref", "refs/remotes/origin/main", "HEAD" })
		git_repo.write(root, "a.lua", { "return 2" })
		git_repo.commit(root, "change")
		package.loaded["unified_review.integrations.gh"] = {
			available = function()
				return true
			end,
			discover_pr_base = function()
				return { number = 7, base_ref = "origin/main", title = "Review me" }, nil
			end,
		}

		local result = assert(discovery.discover({ cwd = root, prefer_jj = false }))
		local items = by_id(result.items)
		local github_item = items["github-pr"]

		assert.is_not_nil(github_item)
		assert.are.equal("github_pr", github_item.target.kind)
		assert.are.equal(7, github_item.target.number)
		assert.are.equal(item_index(result.items, "github-pr") + 1, item_index(result.items, "github-pr-picker"))
		assert.is_nil(items["pr-base"])
	end)

	it("builds jj picker targets from real jj revsets without Git branch heuristics", function()
		local root = jj_repo.create()
		jj_repo.write(root, "a.lua", { "return 1" })
		jj_repo.describe(root, "base")
		jj_repo.remote_bookmark(root, "main", "@")
		jj_repo.new(root)
		jj_repo.write(root, "a.lua", { "return 2" })
		jj_repo.describe(root, "current change")
		package.loaded["unified_review.integrations.gh"] = {
			available = function()
				return false
			end,
		}

		local result = assert(discovery.discover({ cwd = root }))
		local items = by_id(result.items)

		assert.are.equal("jj", result.mode)
		assert.are.same({}, result.warnings)
		assert.is_not_nil(items["jj-current"])
		assert.is_not_nil(items["jj-trunk"])
		assert.is_not_nil(items["jj-main@origin"])
		assert.is_not_nil(items["jj-main@origin-three-dot"])
		assert.is_nil(items["git-origin/main"])
		assert.is_false(items["commit-range"].disabled)
		assert.are.same({}, items["commit-range"].warnings)
		assert.are.equal("jj", items["jj-current"].target.kind)
		assert.are.equal("@-", items["jj-current"].target.base_revset)
		assert.are.equal("@", items["jj-current"].target.head_revset)
		assert.are.equal("two_dot", items["jj-main@origin"].target.range_kind)
		assert.are.equal("three_dot", items["jj-main@origin-three-dot"].target.range_kind)
	end)

	it("uses trunk as the default base for current jj reviews", function()
		local root = jj_repo.create()
		jj_repo.write(root, "a.lua", { "return 1" })
		jj_repo.describe(root, "base")
		jj_repo.new(root)
		jj_repo.write(root, "a.lua", { "return 2" })
		jj_repo.describe(root, "current change")

		local item = assert(discovery.current_target({ cwd = root }))

		assert.are.equal("jj-current-trunk", item.id)
		assert.are.equal("jj", item.target.kind)
		assert.are.equal("trunk()", item.target.base_revset)
		assert.are.equal("@", item.target.head_revset)
		assert.is_false(item.target.current_fallback)
	end)

	it("falls back to the previous mutable jj change when the working-copy commit is empty", function()
		local root = jj_repo.create()
		jj_repo.write(root, "a.lua", { "return 1" })
		jj_repo.describe(root, "base")
		jj_repo.new(root)
		jj_repo.write(root, "a.lua", { "return 2" })
		jj_repo.describe(root, "implemented change")
		local previous_oid = jj_repo.rev_parse(root, "@")
		jj_repo.new(root)

		local item = assert(discovery.current_target({ cwd = root }))

		assert.are.equal("jj-current-fallback", item.id)
		assert.is_true(item.target.current_fallback)
		assert.are.equal("trunk()", item.target.base_revset)
		assert.are.equal(previous_oid, item.target.resolved_head)
		assert.are.equal(previous_oid, item.target.head_revset)
		assert.matches("working%-copy commit has no diff", item.warnings[1])
	end)

	it("uses the jj provider for current reviews even when Git branch state is not useful", function()
		local root = jj_repo.create()
		jj_repo.write(root, "a.lua", { "return 1" })
		jj_repo.describe(root, "base")
		jj_repo.new(root)
		jj_repo.write(root, "a.lua", { "return 2" })
		jj_repo.describe(root, "current change")
		local before_head = git_head_contents(root)

		local item = assert(discovery.current_target({ cwd = root }))
		local after_head = git_head_contents(root)

		assert.are.equal("jj", item.target.kind)
		assert.are.equal("jj", item.badge)
		assert.are.equal(before_head, after_head)
	end)

	it("passes the current jj bookmark to gh PR fallback discovery", function()
		local root = jj_repo.create()
		jj_repo.write(root, "a.lua", { "return 1" })
		jj_repo.describe(root, "base")
		jj_repo.remote_bookmark(root, "main", "@")
		jj_repo.new(root)
		jj_repo.write(root, "a.lua", { "return 2" })
		jj_repo.describe(root, "current change")
		jj_repo.bookmark(root, "feature-bookmark", "@")
		local requested_head
		package.loaded["unified_review.integrations.gh"] = {
			available = function()
				return true
			end,
			discover_pr_base = function(_, opts)
				requested_head = opts.head
				return { number = 9, base_name = "main", title = "Bookmark PR" }, nil
			end,
		}

		local result = assert(discovery.discover({ cwd = root }))
		local items = by_id(result.items)
		local github_item = items["jj-github-pr"]

		assert.are.equal("feature-bookmark", requested_head)
		assert.is_not_nil(github_item)
		assert.are.equal("github_pr", github_item.target.kind)
		assert.are.equal(9, github_item.target.number)
		assert.are.equal(item_index(result.items, "jj-github-pr") + 1, item_index(result.items, "github-pr-picker"))
		assert.is_nil(items["jj-pr-base"])
	end)

	it("uses the closest jj bookmark when the current change has none", function()
		local root = jj_repo.create()
		jj_repo.write(root, "a.lua", { "return 1" })
		jj_repo.describe(root, "base")
		jj_repo.remote_bookmark(root, "main", "@")
		jj_repo.new(root)
		jj_repo.write(root, "a.lua", { "return 2" })
		jj_repo.describe(root, "bookmarked change")
		jj_repo.bookmark(root, "feature-bookmark", "@")
		jj_repo.new(root)
		jj_repo.write(root, "a.lua", { "return 3" })
		jj_repo.describe(root, "descendant change")
		local requested_head
		package.loaded["unified_review.integrations.gh"] = {
			available = function()
				return true
			end,
			discover_pr_base = function(_, opts)
				requested_head = opts.head
				return { number = 10, base_name = "main", title = "Closest bookmark PR" }, nil
			end,
		}

		local result = assert(discovery.discover({ cwd = root }))
		local items = by_id(result.items)

		assert.are.equal("feature-bookmark", requested_head)
		assert.is_not_nil(items["jj-github-pr"])
		assert.are.equal("github_pr", items["jj-github-pr"].target.kind)
		assert.is_nil(items["jj-pr-base"])
	end)

	it("falls back to gh pr list for branch heads when pr view is unavailable", function()
		local gh = require("unified_review.integrations.gh")
		local jobs = require("unified_review.util.jobs")
		local original_run_sync = jobs.run_sync
		local original_available = gh.available
		local calls = {}
		local ok, err = pcall(function()
			rawset(jobs, "run_sync", function(_, args)
				table.insert(calls, args)
				if args[1] == "pr" and args[2] == "view" then
					return { ok = false, code = 1, stdout = "", stderr = "no pull requests found" }
				end
				return {
					ok = true,
					code = 0,
					stderr = "",
					stdout = vim.json.encode({
						{
							number = 12,
							url = "https://example.invalid/pr/12",
							baseRefName = "main",
							headRefName = "feature",
							title = "Fallback PR",
							isDraft = false,
						},
					}),
				}
			end)
			rawset(gh, "available", function()
				return true
			end)

			local pr = assert(gh.discover_pr_base("/repo", { head = "feature" }))

			assert.are.equal(12, pr.number)
			assert.are.equal("origin/main", pr.base_ref)
			assert.are.same({
				"pr",
				"list",
				"--head",
				"feature",
				"--json",
				"number,url,baseRefName,headRefName,title,isDraft",
				"--limit",
				"1",
			}, calls[2])
		end)
		rawset(jobs, "run_sync", original_run_sync)
		rawset(gh, "available", original_available)
		if not ok then
			error(err)
		end
	end)

	it("normalizes GitHub PR picker input", function()
		local target =
			assert(discovery.normalize_github_pr("https://github.com/acme/widgets/pull/42", { cwd = "/repo" }))

		assert.are.equal("github_pr", target.kind)
		assert.are.equal("acme", target.owner)
		assert.are.equal("widgets", target.repo)
		assert.are.equal(42, target.number)
		assert.are.equal("/repo", target.cwd)
	end)

	it("loads open GitHub pull requests for picker selection", function()
		package.loaded["unified_review.integrations.gh"] = {
			list_open_prs = function()
				return {
					{
						number = 42,
						url = "https://github.com/acme/widgets/pull/42",
						title = "Add widgets",
						baseRefName = "main",
						headRefName = "feature",
						author = { login = "octo" },
					},
				},
					nil
			end,
		}

		local prs = assert(discovery.open_pull_requests({ cwd = "/repo" }))

		assert.are.equal(1, #prs)
		assert.are.equal(42, prs[1].number)
		assert.are.equal("octo", prs[1].author)
		assert.are.equal("github_pr", prs[1].target.kind)
		assert.are.equal("feature", prs[1].target.raw_head)
	end)

	it("normalizes Git custom single refs and ranges", function()
		local single = assert(discovery.normalize_custom("origin/main", { mode = "git" }))
		assert.are.equal("local_git", single.kind)
		assert.are.equal("origin/main", single.base)
		assert.are.equal("HEAD", single.head)
		assert.are.equal("three_dot", single.range_kind)

		local range = assert(discovery.normalize_custom("HEAD~3..HEAD", { mode = "git" }))
		assert.are.equal("HEAD~3", range.base)
		assert.are.equal("HEAD", range.head)
		assert.are.equal("two_dot", range.range_kind)
	end)

	it("normalizes jj custom aliases and open-ended ranges with real jj revsets", function()
		local root = jj_repo.create()
		jj_repo.write(root, "a.lua", { "return 1" })
		jj_repo.describe(root, "base")
		local base_oid = jj_repo.rev_parse(root, "@")
		jj_repo.remote_bookmark(root, "main", "@")
		jj_repo.new(root)
		jj_repo.write(root, "a.lua", { "return 2" })
		jj_repo.describe(root, "current")
		local head_oid = jj_repo.rev_parse(root, "@")

		local target = assert(discovery.normalize_custom("origin/main..", { mode = "jj", cwd = root }))
		local explicit = assert(discovery.normalize_custom("trunk()..@", { mode = "jj", cwd = root }))

		assert.are.equal("jj", target.kind)
		assert.are.equal("main@origin", target.base_revset)
		assert.are.equal("@", target.head_revset)
		assert.are.equal(base_oid, target.resolved_base)
		assert.are.equal(head_oid, target.resolved_head)
		assert.are.equal("trunk()", explicit.base_revset)
		assert.are.equal("@", explicit.head_revset)
		assert.are.equal(base_oid, explicit.resolved_base)
		assert.are.equal(head_oid, explicit.resolved_head)
	end)

	it("validates commit ranges using newest-first ordering", function()
		local commits = {
			{ oid = "c3", short_id = "c3", provider = "git" },
			{ oid = "c2", short_id = "c2", provider = "git" },
			{ oid = "c1", short_id = "c1", provider = "git" },
		}

		local range = assert(discovery.validate_commit_range(commits, 3, 1))
		assert.are.equal("c1", range.base.oid)
		assert.are.equal("c3", range.head.oid)
		assert.is_nil(discovery.validate_commit_range(commits, 2, 2))
		local invalid, err = discovery.validate_commit_range(commits, 1, 3)
		assert.is_nil(invalid)
		assert.matches("newer", (err or {}).message or "")
	end)

	it("returns normalized targets from valid commit ranges", function()
		local commits = {
			{ oid = "c3", short_id = "c3", provider = "git" },
			{ oid = "c2", short_id = "c2", provider = "git" },
		}

		local target = assert(discovery.target_from_commit_range(commits, 2, 1, { mode = "git" }))

		assert.are.equal("local_git", target.kind)
		assert.are.equal("c2", target.base)
		assert.are.equal("c3", target.head)
		assert.are.equal("two_dot", target.range_kind)
	end)

	it("opens jj targets through the first-class jj diff provider", function()
		local provider = require("unified_review.providers.diff.jj_local")
		local root = jj_repo.create()
		jj_repo.write(root, "a.lua", { "return 1" })
		jj_repo.describe(root, "base")
		local base_oid = jj_repo.rev_parse(root, "@")
		jj_repo.new(root)
		jj_repo.write(root, "a.lua", { "return 2" })
		jj_repo.describe(root, "current")
		local head_oid = jj_repo.rev_parse(root, "@")

		local session = assert(provider.open({ kind = "jj", root = root, base_revset = "@-", head_revset = "@" }))

		assert.are.equal("jj_local", session.provider)
		assert.is_false(session.editable)
		assert.are.equal(root, session.target.root)
		assert.are.equal(base_oid, session.target.base_oid)
		assert.are.equal(head_oid, session.target.head_oid)
		assert.are.equal(1, #session.files)
		assert.are.equal("a.lua", session.files[1].path)
		assert.are.equal(1, session.files[1].additions)
		assert.are.equal(1, session.files[1].deletions)
		assert.matches("diff %-%-git a/a%.lua b/a%.lua", session.raw_patch)
	end)
end)
