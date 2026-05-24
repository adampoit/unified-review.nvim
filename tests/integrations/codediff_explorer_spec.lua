local state = require("unified_review.session.state")

local function has_codediff_explorer()
	local ok = pcall(require, "codediff.ui.explorer.nodes")
	return ok
end

describe("codediff explorer integration", function()
	after_each(function()
		state.clear_active()
	end)

	it("decorates file rows with review viewed markers", function()
		if not has_codediff_explorer() then
			pending("codediff.nvim explorer is not available")
			return
		end

		local integration = require("unified_review.integrations.codediff_explorer")
		assert.is_true(integration.install())

		state.set_active({
			viewed_files = { ["viewed.lua"] = true, ["resolved.lua"] = true },
			threads = {
				{ state = "resolved", target = { path = "resolved.lua" }, comments = {} },
			},
		})

		local nodes = require("codediff.ui.explorer.nodes")
		local Tree = require("codediff.ui.lib.tree")
		local unviewed = nodes.prepare_node(
			Tree.Node({ text = "unviewed.lua", data = { path = "unviewed.lua", status = "M", status_symbol = "M" } }),
			80
		)
		local viewed = nodes.prepare_node(
			Tree.Node({ text = "viewed.lua", data = { path = "viewed.lua", status = "M", status_symbol = "M" } }),
			80
		)
		local resolved = nodes.prepare_node(
			Tree.Node({ text = "resolved.lua", data = { path = "resolved.lua", status = "M", status_symbol = "M" } }),
			80
		)

		assert.matches("^● ", unviewed:content())
		assert.matches("^  ", viewed:content())
		assert.matches("^✓ ", resolved:content())
		assert.matches("M%s*$", unviewed:content())
		assert.matches("M%s*$", viewed:content())
		assert.matches("M%s*$", resolved:content())
	end)
end)
