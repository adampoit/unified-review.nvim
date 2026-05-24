local gh = require("unified_review.integrations.gh")
local git = require("unified_review.integrations.git")

describe("gh integration", function()
	it("resolves PR metadata from a URL without needing repo context", function()
		local jobs = require("unified_review.util.jobs")
		local original = jobs.run_sync
		local calls = {}
		local ok, err = pcall(function()
			rawset(jobs, "run_sync", function(_, args)
				table.insert(calls, args)
				return {
					ok = true,
					code = 0,
					stderr = "",
					stdout = vim.json.encode({
						id = "PR_kw123",
						number = 42,
						url = "https://github.com/acme/widgets/pull/42",
						title = "Add widgets",
						baseRefName = "main",
						baseRefOid = "baseoid",
						headRefName = "feature",
						headRefOid = "headoid",
					}),
				}
			end)

			local pr = assert(gh.pr_view("/repo", "https://github.com/acme/widgets/pull/42"))

			assert.are.equal("acme", pr.owner)
			assert.are.equal("widgets", pr.repo)
			assert.are.equal(42, pr.number)
			assert.are.equal("PR_kw123", pr.id)
			assert.are.same(
				{ "pr", "view", "https://github.com/acme/widgets/pull/42", "--json", calls[1][5] },
				calls[1]
			)
		end)
		jobs.run_sync = original
		if not ok then
			error(err)
		end
	end)

	it("wraps GraphQL requests through gh api graphql", function()
		local jobs = require("unified_review.util.jobs")
		local original = jobs.run_sync
		local captured
		local ok, err = pcall(function()
			rawset(jobs, "run_sync", function(_, args, opts)
				captured = { args = args, stdin = opts.stdin }
				return { ok = true, code = 0, stderr = "", stdout = vim.json.encode({ data = { ok = true } }) }
			end)

			local result = assert(gh.graphql("query($n:Int!){x}", { n = 1 }, { cwd = "/repo" }))

			assert.is_true(result.data.ok)
			assert.are.same({ "api", "graphql", "--input", "-" }, captured.args)
			local body = vim.json.decode(captured.stdin)
			assert.are.equal("query($n:Int!){x}", body.query)
			assert.are.equal(1, body.variables.n)
		end)
		jobs.run_sync = original
		if not ok then
			error(err)
		end
	end)

	it("resolves a PR from the current branch when gh pr view has no context", function()
		local original_available = gh.available
		local original_current_pr = gh.current_pr
		local original_pr_for_head = gh.pr_for_head
		local original_current_branch = git.current_branch
		local captured_head
		local ok, err = pcall(function()
			rawset(gh, "available", function()
				return true
			end)
			rawset(gh, "current_pr", function()
				return nil, { message = "no current PR" }
			end)
			rawset(git, "current_branch", function(cwd)
				assert.are.equal("/repo", cwd)
				return "feature/login", nil
			end)
			rawset(gh, "pr_for_head", function(_, head)
				captured_head = head
				return {
					number = 17,
					url = "https://github.com/acme/widgets/pull/17",
					baseRefName = "main",
					headRefName = "feature/login",
				},
					nil
			end)

			local pr = assert(gh.resolve_pr_from_branch_context("/repo"))

			assert.are.equal("feature/login", captured_head)
			assert.are.equal(17, pr.number)
		end)
		gh.available = original_available
		gh.current_pr = original_current_pr
		gh.pr_for_head = original_pr_for_head
		git.current_branch = original_current_branch
		if not ok then
			error(err)
		end
	end)
end)
