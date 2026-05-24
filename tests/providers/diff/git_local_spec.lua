local git_local = require("unified_review.providers.diff.git_local")

describe("git local diff provider", function()
	it("finds files in sessions", function()
		local session = {
			files = {
				{ path = "a.lua" },
				{ path = "new.lua", old_path = "old.lua" },
			},
		}

		assert.are.equal("a.lua", git_local.get_file(session, "a.lua").path)
		assert.are.equal("new.lua", git_local.get_file(session, "old.lua").path)
		assert.is_nil(git_local.get_file(session, "missing.lua"))
	end)

	it("maps visual selections to comment targets", function()
		assert.are.same(
			{ kind = "line", path = "a.lua", side = "right", line = 10 },
			git_local.map_visual_range({}, "a.lua", 10, 10, "right")
		)
		assert.are.same({
			kind = "range",
			path = "a.lua",
			start_side = "right",
			start_line = 10,
			side = "right",
			line = 12,
		}, git_local.map_visual_range({}, "a.lua", 10, 12, "right"))
	end)
end)
