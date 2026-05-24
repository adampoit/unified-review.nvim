local publisher = require("unified_review.providers.comments.publish")

local function temp_root()
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	return root
end

local function pr_session(root)
	return {
		id = "github:owner:repo:7",
		kind = "github_pr",
		target = {
			root = root,
			owner = "owner",
			repo = "repo",
			number = 7,
			url = "https://github.com/owner/repo/pull/7",
			pull_request_id = "PR_kw1",
		},
		files = {
			{
				path = "a.lua",
				status = "modified",
				hunks = {
					{
						lines = {
							{ kind = "context", old_line = 1, new_line = 1, text = "local before" },
							{ kind = "added", new_line = 2, text = "publish me" },
							{ kind = "context", old_line = 2, new_line = 3, text = "local after" },
						},
					},
				},
			},
		},
		threads = {},
		metadata = {},
	}
end

describe("draft publishing", function()
	it("publishes local draft comments to a GitHub pending review after anchor remapping", function()
		local graphql = require("unified_review.integrations.github_graphql")
		local original_create = graphql.create_pending_review
		local original_add_thread = graphql.add_thread
		local original_add_reply = graphql.add_reply
		local calls = {}
		local ok, err = pcall(function()
			rawset(graphql, "create_pending_review", function(target)
				table.insert(calls, { op = "create", target = target })
				return "review-1", nil
			end)
			rawset(graphql, "add_thread", function(review_id, target, body)
				table.insert(calls, { op = "thread", review_id = review_id, target = target, body = body })
				return {
					id = "github-thread-1",
					target = target,
					metadata = { github = { id = "github-thread-1" } },
					comments = {
						{
							id = "github-comment-1",
							body = body,
							metadata = { github = { id = "github-comment-1" } },
						},
					},
				},
					nil
			end)
			rawset(graphql, "add_reply", function(thread_id, body)
				table.insert(calls, { op = "reply", thread_id = thread_id, body = body })
				return { id = "github-reply-1", body = body, metadata = { github = { id = "github-reply-1" } } }, nil
			end)
			local root = temp_root()
			local local_session = {
				id = "local:1",
				kind = "local_git",
				target = { root = root },
				threads = {
					{
						id = "thread-local",
						target = { kind = "line", path = "a.lua", side = "right", line = 99 },
						metadata = { export = true, anchor = { side = "right", selected = { "publish me" } } },
						comments = {
							{ id = "comment-local", state = "draft", body = "please fix" },
							{ id = "comment-reply", state = "draft", body = "also this" },
						},
					},
				},
			}

			local report = assert(publisher.publish(local_session, { github_session = pr_session(root) }))

			assert.are.equal("review-1", report.review_id)
			assert.are.equal(2, #report.successes)
			assert.are.equal(0, #report.failures)
			assert.are.equal("create", calls[1].op)
			assert.are.equal("thread", calls[2].op)
			assert.are.equal("review-1", calls[2].review_id)
			assert.are.equal("a.lua", calls[2].target.path)
			assert.are.equal(2, calls[2].target.line)
			assert.are.equal("right", calls[2].target.side)
			assert.are.equal("reply", calls[3].op)
			assert.are.equal("github-thread-1", calls[3].thread_id)
			assert.are.equal("draft", local_session.threads[1].comments[1].state)
			assert.is_not_nil(local_session.threads[1].comments[1].metadata.github)
			assert.are.equal("published", local_session.threads[1].comments[2].metadata.publish.state)
			assert.are.equal(7, local_session.metadata.github_pr_session.number)
		end)
		graphql.create_pending_review = original_create
		graphql.add_thread = original_add_thread
		graphql.add_reply = original_add_reply
		if not ok then
			error(err)
		end
	end)

	it("leaves stale or unmappable comments local and marks publish_failed", function()
		local graphql = require("unified_review.integrations.github_graphql")
		local original_create = graphql.create_pending_review
		local original_add_thread = graphql.add_thread
		local remote_called = false
		local ok, err = pcall(function()
			rawset(graphql, "create_pending_review", function()
				return "review-1", nil
			end)
			rawset(graphql, "add_thread", function()
				remote_called = true
				return nil, { message = "should not be called" }
			end)
			local root = temp_root()
			local local_session = {
				id = "local:1",
				kind = "local_git",
				target = { root = root },
				threads = {
					{
						id = "thread-stale",
						state = "stale",
						target = { kind = "line", path = "a.lua", side = "right", line = 42 },
						metadata = { export = true },
						comments = { { id = "comment-stale", state = "draft", body = "lost" } },
					},
				},
			}

			local report = assert(publisher.publish(local_session, { github_session = pr_session(root) }))

			assert.is_false(remote_called)
			assert.are.equal(0, #report.successes)
			assert.are.equal(1, #report.failures)
			assert.matches("not present", report.failures[1].reason)
			assert.are.equal("publish_failed", local_session.threads[1].comments[1].state)
			assert.are.equal("failed", local_session.threads[1].comments[1].metadata.publish.state)
		end)
		graphql.create_pending_review = original_create
		graphql.add_thread = original_add_thread
		if not ok then
			error(err)
		end
	end)
end)
