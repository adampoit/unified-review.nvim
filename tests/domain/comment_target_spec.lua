local target = require("unified_review.domain.comment_target")

describe("comment_target", function()
	it("creates line targets", function()
		assert.are.same({
			kind = "line",
			path = "lua/init.lua",
			side = "right",
			line = 12,
		}, target.line({ path = "lua/init.lua", side = "right", line = 12 }))
	end)

	it("creates range targets", function()
		assert.are.same({
			kind = "range",
			path = "lua/init.lua",
			start_side = "left",
			start_line = 4,
			side = "right",
			line = 8,
		}, target.range({ path = "lua/init.lua", start_side = "left", start_line = 4, side = "right", line = 8 }))
	end)

	it("compares targets", function()
		local left = target.line({ path = "a.lua", side = "right", line = 2 })
		local right = target.line({ path = "a.lua", side = "right", line = 2 })
		local other = target.line({ path = "a.lua", side = "left", line = 2 })

		assert.is_true(target.equals(left, right))
		assert.is_false(target.equals(left, other))
	end)

	it("labels targets", function()
		assert.are.equal("a.lua", target.label(target.file({ path = "a.lua" })))
		assert.are.equal("a.lua:right:2", target.label(target.line({ path = "a.lua", side = "right", line = 2 })))
	end)

	it("validates required fields", function()
		assert.has_error(function()
			target.line({ side = "right", line = 1 })
		end, "path is required")
	end)
end)
