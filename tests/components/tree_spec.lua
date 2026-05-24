local renderer = require("components.renderer")
local tree = require("components.tree")

local function lines(document)
	return renderer.lines(document)
end

describe("tree component", function()
	it("flattens expanded nodes with depth metadata", function()
		local nodes = {
			{
				kind = "parent",
				id = "a",
				children = {
					{ kind = "child", id = "a.1" },
				},
			},
			{ kind = "parent", id = "b", collapsed = true, children = { { kind = "child", id = "b.1" } } },
		}

		local entries = tree.flatten(nodes, {
			key = function(node)
				return node.id
			end,
			expanded = function(node)
				return not node.collapsed
			end,
		})

		assert.are.equal(3, #entries)
		assert.are.equal("a", entries[1].key)
		assert.are.equal(0, entries[1].depth)
		assert.are.equal("a.1", entries[2].key)
		assert.are.equal(1, entries[2].depth)
		assert.are.equal("b", entries[3].key)
	end)

	it("renders through the list component and exposes row metadata", function()
		local result = tree.list({ { id = "root", label = "root", children = { { id = "leaf", label = "leaf" } } } }, {
			selectable = true,
			selected_key = "leaf",
			key = function(node)
				return node.id
			end,
			prefix = function(ctx)
				return string.rep(".", ctx.depth) .. ctx.marker .. " "
			end,
			render = function(node)
				return node.label
			end,
			row = function(_, ctx)
				return { key = ctx.key, depth = ctx.depth, selected = ctx.selected }
			end,
		})

		assert.are.same({ "  root", ".› leaf" }, lines(result.document))
		assert.are.equal("leaf", result.rows[2].key)
		assert.are.equal(1, result.rows[2].depth)
		assert.is_true(result.rows[2].selected)
	end)
end)
