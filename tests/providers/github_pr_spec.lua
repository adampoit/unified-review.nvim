local provider = require("unified_review.providers.diff.github_pr")
local diff_builder = require("helpers.diff_builder")

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
