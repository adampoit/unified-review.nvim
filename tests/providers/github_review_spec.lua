local provider = require("unified_review.providers.comments.github_review")
local session_store = require("unified_review.persist.session_store")

local function temp_session(extra)
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	return vim.tbl_deep_extend("force", {
		id = "github:owner:repo:1",
		kind = "github_pr",
		target = { root = root, pull_request_id = "pr1" },
		threads = {},
		metadata = {},
	}, extra or {})
end

describe("GitHub review comment provider", function()
	it("keeps new PR comments as local drafts", function()
		local graphql = require("unified_review.integrations.github_graphql")
		local original_create = graphql.create_pending_review
		local original_add = graphql.add_thread
		local called_remote = false
		local ok, err = pcall(function()
			rawset(graphql, "create_pending_review", function()
				called_remote = true
				return "review1", nil
			end)
			rawset(graphql, "add_thread", function()
				called_remote = true
				return nil, { message = "should not publish while drafting" }
			end)
			local session = temp_session()

			local thread = assert(
				provider.create_thread(session, { kind = "line", path = "a.lua", side = "right", line = 3 }, "hi")
			)

			assert.is_nil(session.metadata.github)
			assert.are.equal(thread.id, session.threads[1].id)
			assert.are.equal("draft", thread.comments[1].state)
			assert.is_true(thread.metadata.export)
			assert.is_false(called_remote)
		end)
		graphql.create_pending_review = original_create
		graphql.add_thread = original_add
		if not ok then
			error(err)
		end
	end)

	it("publishes exported local drafts to a GitHub pending review", function()
		local graphql = require("unified_review.integrations.github_graphql")
		local original_create = graphql.create_pending_review
		local original_add = graphql.add_thread
		local original_reply = graphql.add_reply
		local calls = {}
		local ok, err = pcall(function()
			rawset(graphql, "create_pending_review", function()
				table.insert(calls, "create_review")
				return "review1", nil
			end)
			rawset(graphql, "add_thread", function(review_id, target, body)
				table.insert(calls, { op = "thread", review_id = review_id, target = target, body = body })
				return {
					id = "remote-thread1",
					target = target,
					state = "open",
					metadata = { github = { id = "remote-thread1" } },
					comments = { { id = "remote-comment1", state = "remote", body = body, target = target } },
				},
					nil
			end)
			rawset(graphql, "add_reply", function(thread_id, body)
				table.insert(calls, { op = "reply", thread_id = thread_id, body = body })
				return { id = "remote-reply", state = "remote", body = body }, nil
			end)
			local session = temp_session()
			local thread = assert(
				provider.create_thread(session, { kind = "line", path = "a.lua", side = "right", line = 3 }, "hi")
			)
			assert(provider.reply(session, thread.id, "again"))

			local result = assert(provider.publish_drafts(session))

			assert.are.equal("review1", session.metadata.github.pending_review_id)
			assert.are.equal(2, result.comments)
			assert.are.equal("create_review", calls[1])
			assert.are.equal("review1", calls[2].review_id)
			assert.are.equal("hi", calls[2].body)
			assert.are.equal("remote-thread1", calls[3].thread_id)
			assert.are.equal("again", calls[3].body)
			assert.are.equal("remote-thread1", session.threads[1].id)
			assert.are.equal("draft", session.threads[1].comments[1].state)
			assert.is_not_nil(session.threads[1].comments[1].metadata.github)
			assert.are.equal("review1", session.threads[1].comments[1].metadata.github_pending_review_id)
			assert.are.equal("draft", session.threads[1].comments[2].state)
			assert.is_not_nil(session.threads[1].comments[2].metadata.github)
		end)
		graphql.create_pending_review = original_create
		graphql.add_thread = original_add
		graphql.add_reply = original_reply
		if not ok then
			error(err)
		end
	end)

	it("applies persisted export marks and merges local drafts when loading remote threads", function()
		local graphql = require("unified_review.integrations.github_graphql")
		local original_fetch = graphql.fetch_review_threads
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		local stored = {
			id = "github:owner:repo:1",
			kind = "github_pr",
			target = { root = root },
			threads = {
				{
					id = "thread1",
					metadata = { export = false },
					target = { kind = "file", path = "a.lua" },
					comments = { { body = "stored", state = "remote" } },
				},
				{
					id = "remote-draft-thread",
					metadata = { github = { id = "remote-draft-thread" }, export = true },
					target = { kind = "line", path = "a.lua", side = "right", line = 2 },
					comments = {
						{
							id = "remote-draft-comment",
							body = "remote draft",
							state = "draft",
							metadata = { github = { id = "remote-draft-comment" } },
						},
					},
				},
				{
					id = "local-thread",
					metadata = { export = true },
					target = { kind = "line", path = "b.lua", side = "right", line = 2 },
					comments = { { id = "comment1", body = "draft", state = "draft" } },
				},
			},
		}
		session_store.write(stored)
		local ok, err = pcall(function()
			rawset(graphql, "fetch_review_threads", function()
				return {
					{
						id = "thread1",
						state = "open",
						metadata = { github = { id = "thread1" } },
						target = { kind = "file", path = "a.lua" },
						comments = { { body = "remote", state = "remote" } },
					},
					{
						id = "remote-draft-thread",
						state = "open",
						metadata = { github = { id = "remote-draft-thread" } },
						target = { kind = "line", path = "a.lua", side = "right", line = 2 },
						comments = {
							{
								id = "remote-draft-comment",
								body = "remote draft",
								state = "remote",
								metadata = { github = { id = "remote-draft-comment" } },
							},
						},
					},
				},
					nil
			end)
			local session = { id = stored.id, kind = "github_pr", target = { root = root } }

			local threads = assert(provider.load(session))

			assert.is_false(threads[1].metadata.export)
			assert.are.equal("remote-draft-thread", threads[2].id)
			assert.are.equal("draft", threads[2].comments[1].state)
			assert.is_not_nil(threads[2].comments[1].metadata.github)
			assert.are.equal("local-thread", threads[3].id)
			assert.are.equal("draft", threads[3].comments[1].state)
		end)
		graphql.fetch_review_threads = original_fetch
		if not ok then
			error(err)
		end
	end)

	it("deletes remote draft comments from the pending GitHub review", function()
		local graphql = require("unified_review.integrations.github_graphql")
		local original_delete = graphql.delete_review_comment
		local deleted_id
		local ok, err = pcall(function()
			rawset(graphql, "delete_review_comment", function(comment_id)
				deleted_id = comment_id
				return { pullRequestReviewComment = { id = comment_id } }, nil
			end)
			local session = temp_session({
				threads = {
					{
						id = "remote-thread1",
						state = "open",
						metadata = { github = { id = "remote-thread1" } },
						target = { kind = "line", path = "a.lua", side = "right", line = 3 },
						comments = {
							{
								id = "local-comment1",
								state = "draft",
								body = "pending",
								metadata = { github = { id = "remote-comment1" } },
							},
						},
					},
				},
			})

			assert(provider.delete_draft(session, "local-comment1"))

			assert.are.equal("remote-comment1", deleted_id)
			assert.are.equal(0, #session.threads)
		end)
		graphql.delete_review_comment = original_delete
		if not ok then
			error(err)
		end
	end)

	it("submits pending reviews and clears the pending id", function()
		local graphql = require("unified_review.integrations.github_graphql")
		local original_submit = graphql.submit_review
		local captured
		local ok, err = pcall(function()
			rawset(graphql, "submit_review", function(review_id, event, body)
				captured = { review_id = review_id, event = event, body = body }
				return { id = review_id, state = "SUBMITTED" }, nil
			end)
			local session = {
				kind = "github_pr",
				metadata = { github = { pending_review_id = "review1" } },
				threads = {
					{
						comments = {
							{ state = "draft", metadata = { github = { id = "remote-comment" } } },
							{ state = "draft" },
						},
						metadata = { export = false },
					},
				},
			}

			assert(provider.submit_review(session, "APPROVE", "ship it"))

			assert.are.equal("review1", captured.review_id)
			assert.are.equal("APPROVE", captured.event)
			assert.is_nil(session.metadata.github.pending_review_id)
			assert.are.equal("remote", session.threads[1].comments[1].state)
			assert.are.equal("draft", session.threads[1].comments[2].state)
		end)
		graphql.submit_review = original_submit
		if not ok then
			error(err)
		end
	end)
end)
