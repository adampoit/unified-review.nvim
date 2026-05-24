local export = require("unified_review.export")

local function thread(opts)
	return vim.tbl_deep_extend("force", {
		id = "thread-1",
		state = "open",
		target = { kind = "line", path = "a.lua", side = "right", line = 10 },
		comments = {
			{ id = "comment-1", author = "Ada", created_at = "2026-01-01T00:00:00Z", body = "Please simplify this." },
		},
		metadata = { export = true },
	}, opts or {})
end

describe("review export", function()
	it("formats an empty review", function()
		assert.are.equal("", export.format({}, { format = "minimal" }))
		assert.are.equal("", export.format({}, { format = "markdown" }))
	end)

	it("exports only marked threads by default", function()
		local text = export.format({ thread({ metadata = { export = false } }) }, { format = "minimal" })
		assert.are.equal("", text)
	end)

	it("exports draft threads by default", function()
		local text = export.format({
			thread({
				metadata = {},
				comments = {
					{ id = "comment-1", state = "draft", author = "Ada", body = "Draft note." },
				},
			}),
		}, { format = "minimal" })
		assert.are.equal("a.lua:L10: Draft note.", text)
	end)

	it("formats minimal line comments", function()
		local text = export.format({ thread() }, { format = "minimal" })
		assert.are.equal("a.lua:L10: Please simplify this.", text)
	end)

	it("formats range and file targets for minimal output", function()
		local text = export.format({
			thread({
				target = {
					kind = "range",
					path = "b.lua",
					start_line = 2,
					start_side = "right",
					line = 4,
					side = "right",
				},
			}),
			thread({ id = "thread-2", target = { kind = "file", path = "c.lua" } }),
		}, { format = "minimal" })
		assert.matches("b.lua:L2%-L4: Please simplify this%.", text)
		assert.matches("c.lua: Please simplify this%.", text)
	end)

	it("formats detailed markdown without internal thread IDs", function()
		local text = export.format({
			thread({
				state = "resolved",
				comments = {
					{ author = "Ada", created_at = "2026-01-01T00:00:00Z", body = "Please simplify this." },
					{ author = "Claude", created_at = "2026-01-01T00:01:00Z", body = "Done." },
				},
			}),
		}, { format = "markdown" })
		assert.matches("# Code Review", text)
		assert.matches("## a%.lua", text)
		assert.matches("%*%*Status%*%*: `resolved`", text)
		assert.not_matches("%*%*Thread%*%*", text)
		assert.not_matches("thread%-1", text)
		assert.matches("Please simplify this%.", text)
		assert.matches("Done%.", text)
	end)

	it("saves formatted review text", function()
		local path = vim.fn.tempname()
		export.save(path, { thread() }, { format = "minimal" })
		assert.are.equal("a.lua:L10: Please simplify this.", table.concat(vim.fn.readfile(path), "\n"))
	end)
end)
