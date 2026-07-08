local agent_feedback = require("unified_review.agent_feedback")
local state = require("unified_review.session.state")

local function active_session()
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	vim.fn.writefile({ "print('hello')" }, root .. "/a.lua")
	local session = {
		id = "session-agent",
		kind = "local_git",
		target = { root = root, base_oid = "base", head_oid = "head" },
		files = {
			{
				path = "a.lua",
				status = "modified",
				additions = 1,
				deletions = 0,
				raw_patch = "@@ -1 +1 @@",
				hunks = {},
			},
		},
		selection = { file_index = 1 },
		threads = {},
	}
	state.set_active(session)
	return session
end

describe("agent feedback", function()
	after_each(function()
		state.clear_active()
	end)

	it("imports file, line, and range comments with agent metadata", function()
		local session = active_session()
		local result = assert(agent_feedback.import({
			schema = "unified-review.agent-feedback.v1",
			author = "pi-agent",
			source = { name = "pi", run_id = "run-1" },
			comments = {
				{ id = "file", body = "file note", target = { kind = "file", path = "a.lua" } },
				{
					id = "line",
					body = "line note",
					target = { kind = "line", path = "a.lua", side = "right", line = 1 },
				},
				{
					id = "range",
					body = "range note",
					target = {
						kind = "range",
						path = "a.lua",
						start_side = "right",
						start_line = 1,
						side = "right",
						line = 1,
					},
				},
			},
		}, { refresh_ui = false }))

		assert.are.equal(3, result.imported_threads)
		assert.are.equal(3, result.imported_comments)
		assert.are.equal(3, #session.threads)
		assert.are.equal("pi-agent", session.threads[1].comments[1].author)
		assert.are.equal("pi", session.threads[1].metadata.agent_feedback.source.name)
	end)

	it("skips comments for files outside the active session", function()
		active_session()
		local result = assert(agent_feedback.import({
			schema = "unified-review.agent-feedback.v1",
			comments = {
				{ body = "missing", target = { kind = "file", path = "missing.lua" } },
			},
		}, { refresh_ui = false }))

		assert.are.equal(0, result.imported_comments)
		assert.are.equal(1, #result.skipped)
	end)

	it("deduplicates stable agent comment ids", function()
		local session = active_session()
		local review = {
			schema = "unified-review.agent-feedback.v1",
			source = { name = "pi", run_id = "run-1" },
			comments = {
				{ id = "c1", body = "first", target = { kind = "file", path = "a.lua" } },
			},
		}
		assert(agent_feedback.import(review, { refresh_ui = false }))
		review.comments[1].body = "updated"
		local result = assert(agent_feedback.import(review, { refresh_ui = false }))

		assert.are.equal(1, #session.threads)
		assert.are.equal(1, result.updated_threads)
		assert.are.equal("updated", session.threads[1].comments[1].body)
	end)

	it("writes diff-focused context", function()
		active_session()
		local context = assert(agent_feedback.context({}))

		assert.are.equal("unified-review.agent-context.v1", context.schema)
		assert.are.equal("session-agent", context.session.id)
		assert.are.equal("a.lua", context.files[1].path)
		assert.are.equal("@@ -1 +1 @@", context.files[1].raw_patch)
	end)
end)
