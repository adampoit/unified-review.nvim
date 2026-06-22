local ui = require("components")
local renderer = require("components.renderer")

describe("ui component renderer", function()
	it("flattens component lines and highlight spans", function()
		local flattened = renderer.flatten({
			ui.line({
				ui.list({
					{ ui.badge("j/k", { hl = "KeyHl" }), ui.text("move") },
					{ ui.badge("git", { hl = "BadgeHl" }), ui.text("target") },
				}, { type = "horizontal" }),
			}),
			ui.blank(),
			ui.text_line("Provider: git", "ContextHl"),
		})

		assert.are.same({ " j/k  move ·  git  target", "", "Provider: git" }, flattened.lines)
		assert.are.equal("KeyHl", flattened.highlights[1].group)
		assert.are.equal(0, flattened.highlights[1].start_col)
		assert.are.equal(5, flattened.highlights[1].end_col)
		assert.are.equal("BadgeHl", flattened.highlights[2].group)
		assert.are.equal("ContextHl", flattened.highlights[3].group)
	end)

	it("accepts plain strings during migration", function()
		local flattened = renderer.flatten({ "plain", ui.divider(10, { hl = "DividerHl" }) })

		assert.are.same({ "plain", "──────────" }, flattened.lines)
		assert.are.equal("DividerHl", flattened.highlights[1].group)
	end)

	it("renders loader frames as a stable-width multi-dot braille spinner", function()
		local flattened = renderer.flatten({
			ui.line({ ui.loader("Loading", { frame = 0, hl = "TextHl", spinner_hl = "SpinnerHl" }) }),
			ui.line({ ui.loader("Loading", { frame = 2, hl = "TextHl", spinner_hl = "SpinnerHl" }) }),
		})

		assert.are.same({ "⠋ Loading", "⠹ Loading" }, flattened.lines)
		assert.are.equal("SpinnerHl", flattened.highlights[1].group)
		assert.are.equal(0, flattened.highlights[1].start_col)
		assert.are.equal(#"⠋", flattened.highlights[1].end_col)
		assert.are.equal("TextHl", flattened.highlights[2].group)
	end)

	it("keeps badge spacing in horizontal lists instead of badge rendering", function()
		local flattened = renderer.flatten({
			ui.line({ ui.badge("git", { hl = "BadgeHl" }), ui.text("target") }),
			ui.line({
				ui.list({ { ui.badge("git", { hl = "BadgeHl" }), ui.text("target") } }, { type = "horizontal" }),
			}),
			ui.line({ ui.list({ { ui.badge("", { hl = "BadgeHl" }), ui.text("empty") } }, { type = "horizontal" }) }),
		})

		assert.are.same({ " git target", " git  target", "empty" }, flattened.lines)
	end)

	it("insets documents while preserving blank lines and content truncation", function()
		local document = ui.inset({
			ui.line({ ui.text("abcdef", "TextHl") }, { hl = "RowHl", truncate_width = 4 }),
			ui.blank(),
			"plain",
		}, { left = 2 })
		local flattened = renderer.flatten(document)

		assert.are.same({ "  abc…", "", "  plain" }, flattened.lines)
		assert.are.equal("RowHl", flattened.highlights[1].group)
		assert.are.equal("TextHl", flattened.highlights[2].group)
		assert.are.equal(2, flattened.highlights[2].start_col)
	end)

	it("builds vertical lists with a centered viewport and row metadata", function()
		local result = ui.list({ "a", "b", "c", "d" }, {
			height = 3,
			selected = 3,
			render = function(item, ctx)
				return ui.text_line(tostring(ctx.index) .. ":" .. item)
			end,
		})
		local flattened = renderer.flatten(result.document)

		assert.are.same({ "2:b", "3:c", "4:d" }, flattened.lines)
		assert.are.equal(2, result.first)
		assert.are.equal(4, result.last)
		assert.are.equal(3, result.rows[2].index)
		assert.is_true(result.rows[2].selected)
	end)

	it("builds selectable lists with markers, selected highlights, and padding", function()
		local result = ui.list({ "a", "b" }, {
			selectable = true,
			height = 3,
			selected = 2,
			selected_hl = "SelectedHl",
			render = function(item)
				return ui.text(item)
			end,
		})
		local flattened = renderer.flatten(result.document)

		assert.are.same({ "  a", "› b", "" }, flattened.lines)
		assert.are.equal("SelectedHl", flattened.highlights[1].group)
		assert.are.equal(1, result.rows[1].index)
		assert.are.equal(2, result.rows[2].index)
	end)

	it("can apply a full-line highlight without hiding inline spans", function()
		local flattened = renderer.flatten({
			ui.line({
				ui.text("› "),
				ui.list({ { ui.badge("git", { hl = "BadgeHl" }), ui.text("target") } }, { type = "horizontal" }),
			}, { hl = "RowHl" }),
		})

		assert.are.same({ "›  git  target" }, flattened.lines)
		assert.are.equal("RowHl", flattened.highlights[1].group)
		assert.are.equal("BadgeHl", flattened.highlights[2].group)
	end)

	it("truncates display text and clamps highlight spans", function()
		local flattened = renderer.flatten({
			ui.line({ ui.text("abcdef", "TextHl"), ui.text("ghij", "TailHl") }, { truncate_width = 6 }),
		})

		assert.are.same({ "abcde…" }, flattened.lines)
		assert.are.equal("TextHl", flattened.highlights[1].group)
		assert.are.equal(0, flattened.highlights[1].start_col)
		assert.are.equal(5, flattened.highlights[1].end_col)
		assert.is_nil(flattened.highlights[2])
	end)

	it("truncates wide characters by display width", function()
		local flattened = renderer.flatten({
			ui.line({ ui.text("abc漢字", "TextHl") }, { truncate_width = 6 }),
		})

		assert.are.same({ "abc漢…" }, flattened.lines)
		assert.are.equal("TextHl", flattened.highlights[1].group)
		assert.are.equal(#"abc漢", flattened.highlights[1].end_col)
	end)

	it("pads and truncates inline fragments without losing child spans", function()
		local flattened = renderer.flatten({
			ui.line({
				ui.pad_left(ui.text("7", "NumberHl"), 3),
				ui.text("|"),
				ui.pad_right(ui.text("ok", "StateHl"), 5),
				ui.text("|"),
				ui.truncate(ui.text("abcdef", "BodyHl"), 4),
			}),
		})

		assert.are.same({ "  7|ok   |abc…" }, flattened.lines)
		assert.are.equal("NumberHl", flattened.highlights[1].group)
		assert.are.equal(2, flattened.highlights[1].start_col)
		assert.are.equal(3, flattened.highlights[1].end_col)
		assert.are.equal("StateHl", flattened.highlights[2].group)
		assert.are.equal("BodyHl", flattened.highlights[3].group)
		assert.are.equal(10, flattened.highlights[3].start_col)
		assert.are.equal(13, flattened.highlights[3].end_col)
	end)

	it("renders fixed-width columns with alignment and separators", function()
		local flattened = renderer.flatten({
			ui.columns({
				{ ui.text("open", "StateHl"), width = 8 },
				{ ui.text("12", "CountHl"), width = 4, align = "right" },
				{ ui.text("long body text", "BodyHl"), width = 9 },
			}, { separator = " │ ", separator_hl = "SepHl" }),
		})

		assert.are.same({ "open     │   12 │ long bod…" }, flattened.lines)
		assert.are.equal("StateHl", flattened.highlights[1].group)
		assert.are.equal("SepHl", flattened.highlights[2].group)
		assert.are.equal("CountHl", flattened.highlights[3].group)
		assert.are.equal("BodyHl", flattened.highlights[5].group)
	end)

	it("renders to a Neovim buffer and applies extmarks", function()
		local buf = vim.api.nvim_create_buf(false, true)
		local ns = vim.api.nvim_create_namespace("components_renderer_spec")
		local rendered = renderer.render(buf, ns, {
			ui.text_line("hello", "HelloHl"),
			ui.line({ ui.list({ { ui.badge("ok", { hl = "BadgeHl" }), ui.text("done") } }, { type = "horizontal" }) }),
		})
		local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })

		assert.are.same({ "hello", " ok  done" }, rendered.lines)
		assert.are.same(rendered.lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
		assert.are.equal(2, #marks)
		assert.are.equal("HelloHl", marks[1][4].hl_group)
		assert.are.equal("BadgeHl", marks[2][4].hl_group)
	end)
end)
