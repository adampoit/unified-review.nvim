local graphql = require("unified_review.integrations.github_graphql")

describe("github GraphQL integration", function()
	it("normalizes review threads and comments", function()
		local thread = graphql.normalize_thread({
			id = "thread1",
			isResolved = false,
			isOutdated = true,
			path = "lua/a.lua",
			line = 12,
			startLine = 10,
			diffSide = "RIGHT",
			comments = {
				nodes = {
					{
						id = "comment1",
						body = "Looks good",
						createdAt = "2026-01-01T00:00:00Z",
						author = { login = "octo" },
					},
				},
			},
		})

		assert.are.equal("thread1", thread.id)
		assert.are.equal("stale", thread.state)
		assert.is_true(thread.is_outdated)
		assert.are.equal("range", thread.target.kind)
		assert.are.equal(10, thread.target.start_line)
		assert.are.equal(12, thread.target.line)
		assert.are.equal("octo", thread.comments[1].author)
		assert.are.equal("remote", thread.comments[1].state)
	end)

	it("marks pending GitHub review comments as remote drafts", function()
		local thread = graphql.normalize_thread({
			id = "thread1",
			path = "a.lua",
			line = 1,
			diffSide = "RIGHT",
			comments = {
				nodes = {
					{
						id = "comment1",
						body = "pending comment",
						state = "PENDING",
						pullRequestReview = { id = "review1", state = "PENDING" },
					},
				},
			},
		})

		assert.are.equal("draft", thread.comments[1].state)
		assert.are.equal("review1", thread.comments[1].metadata.github_pending_review_id)
	end)

	it("treats JSON null values from gh as absent fields", function()
		local thread = graphql.normalize_thread({
			id = "thread-null-line",
			isResolved = vim.NIL,
			isOutdated = vim.NIL,
			path = "lua/a.lua",
			line = vim.NIL,
			startLine = vim.NIL,
			originalLine = vim.NIL,
			originalStartLine = vim.NIL,
			diffSide = vim.NIL,
			comments = {
				nodes = {
					{
						id = "comment-null-author",
						body = vim.NIL,
						createdAt = vim.NIL,
						author = { login = vim.NIL },
					},
				},
			},
		})

		assert.are.equal("file", thread.target.kind)
		assert.are.equal("lua/a.lua", thread.target.path)
		assert.are.equal("open", thread.state)
		assert.is_false(thread.is_outdated)
		assert.are.equal(" ", thread.comments[1].body)
		assert.are.equal("github", thread.comments[1].author)
	end)

	it("accepts gh api graphql responses wrapped in top-level data", function()
		local gh = require("unified_review.integrations.gh")
		local original = gh.graphql
		local ok, err = pcall(function()
			rawset(gh, "graphql", function()
				return {
					data = {
						repository = {
							pullRequest = {
								reviewThreads = {
									pageInfo = { hasNextPage = false },
									nodes = {
										{
											id = "thread1",
											path = "a.lua",
											line = 1,
											diffSide = "RIGHT",
											comments = { nodes = { { id = "comment1", body = "remote thread" } } },
										},
									},
								},
							},
						},
					},
				},
					nil
			end)

			local threads = assert(graphql.fetch_review_threads({ owner = "acme", repo = "widgets", number = 1 }))

			assert.are.equal(1, #threads)
			assert.are.equal("remote thread", threads[1].comments[1].body)
		end)
		gh.graphql = original
		if not ok then
			error(err)
		end
	end)

	it("creates pending reviews by omitting the event", function()
		local gh = require("unified_review.integrations.gh")
		local original = gh.graphql
		local captured
		local ok, err = pcall(function()
			rawset(gh, "graphql", function(_, variables)
				captured = variables.input
				return { addPullRequestReview = { pullRequestReview = { id = "review1" } } }, nil
			end)

			local review_id = assert(graphql.create_pending_review({ id = "pr1" }))

			assert.are.equal("review1", review_id)
			assert.are.equal("pr1", captured.pullRequestId)
			assert.is_nil(captured.event)
		end)
		gh.graphql = original
		if not ok then
			error(err)
		end
	end)

	it("deletes pull request review comments by node id", function()
		local gh = require("unified_review.integrations.gh")
		local original = gh.graphql
		local captured_query
		local captured_input
		local ok, err = pcall(function()
			rawset(gh, "graphql", function(query, variables)
				captured_query = query
				captured_input = variables.input
				return {
					deletePullRequestReviewComment = {
						pullRequestReviewComment = { id = variables.input.id },
					},
				},
					nil
			end)

			local result = assert(graphql.delete_review_comment("comment1"))

			assert.matches("deletePullRequestReviewComment", captured_query)
			assert.are.equal("comment1", captured_input.id)
			assert.are.equal("comment1", result.pullRequestReviewComment.id)
		end)
		gh.graphql = original
		if not ok then
			error(err)
		end
	end)

	it("paginates review thread queries", function()
		local gh = require("unified_review.integrations.gh")
		local original = gh.graphql
		local calls = {}
		local ok, err = pcall(function()
			rawset(gh, "graphql", function(_, variables)
				table.insert(calls, variables.after or vim.NIL)
				return {
					repository = {
						pullRequest = {
							reviewThreads = {
								pageInfo = { hasNextPage = variables.after == nil, endCursor = "cursor2" },
								nodes = {
									{
										id = "thread" .. tostring(#calls),
										path = "a.lua",
										line = 1,
										diffSide = "RIGHT",
										comments = { nodes = { { id = "c" .. tostring(#calls), body = "body" } } },
									},
								},
							},
						},
					},
				},
					nil
			end)

			local threads = assert(graphql.fetch_review_threads({ owner = "acme", repo = "widgets", number = 1 }))

			assert.are.equal(2, #threads)
			assert.are.same({ vim.NIL, "cursor2" }, calls)
		end)
		gh.graphql = original
		if not ok then
			error(err)
		end
	end)
end)
