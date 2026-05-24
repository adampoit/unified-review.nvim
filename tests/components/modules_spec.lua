local renderer = require("components.renderer")

describe("ui component modules", function()
	it("exposes primitive constructors from dedicated modules", function()
		local badge = require("components.badge")
		local blank = require("components.blank")
		local columns = require("components.columns")
		local divider = require("components.divider")
		local line = require("components.line")
		local pad_left = require("components.pad_left")
		local pad_right = require("components.pad_right")
		local section = require("components.section")
		local sep = require("components.sep")
		local space = require("components.space")
		local text = require("components.text")
		local text_line = require("components.text_line")
		local tree = require("components.tree")
		local truncate = require("components.truncate")

		assert.are.equal("function", type(tree.list))

		local nodes = {
			text.component("body"),
			line.component({ text.component("row") }),
			text_line.component("whole row"),
			blank.component(),
			badge.component("ok"),
			sep.component(),
			divider.component(12),
			section.component("Title"),
			space.component(2),
			pad_left.component(text.component("7"), 3),
			pad_right.component(text.component("ok"), 4),
			truncate.component(text.component("abcdef"), 4),
			columns.component({
				{ text.component("left"), width = 6 },
				{ text.component("9"), width = 2, align = "right" },
			}),
		}

		assert.are.same(
			{
				"text",
				"line",
				"text_line",
				"blank",
				"badge",
				"sep",
				"divider",
				"section",
				"space",
				"pad_left",
				"pad_right",
				"truncate",
				"columns",
			},
			vim.tbl_map(function(node)
				return node.kind
			end, nodes)
		)
	end)

	it("keeps module constructors render-compatible", function()
		local columns = require("components.columns")
		local line = require("components.line")
		local text = require("components.text")

		local flattened = renderer.flatten({
			line.component({
				columns.component({
					{ text.component("open", "StateHl"), width = 6 },
					{ text.component("12", "CountHl"), width = 3, align = "right" },
				}, { separator = " │ " }),
			}),
		})

		assert.are.same({ "open   │  12" }, flattened.lines)
		assert.are.equal("StateHl", flattened.highlights[1].group)
		assert.are.equal("CountHl", flattened.highlights[2].group)
	end)
end)
