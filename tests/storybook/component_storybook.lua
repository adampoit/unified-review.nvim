local ui = require("components")
local renderer = require("components.renderer")

local M = {}

local palette = {
	ComponentStorybookNormal = { fg = "#cdd6f4", bg = "#07080d" },
	ComponentStorybookBorder = { fg = "#89b4fa", bg = "#07080d" },
	ComponentStorybookTitle = { fg = "#f5c2e7", bold = true },
	ComponentStorybookText = { fg = "#cdd6f4" },
	ComponentStorybookMuted = { fg = "#7f849c" },
	ComponentStorybookAccent = { fg = "#89b4fa", bold = true },
	ComponentStorybookBadge = { fg = "#11111b", bg = "#89b4fa", bold = true },
	ComponentStorybookWarning = { fg = "#11111b", bg = "#fab387", bold = true },
	ComponentStorybookSeparator = { fg = "#585b70" },
	ComponentStorybookSelection = { bg = "#313244" },
	ComponentStorybookState = { fg = "#a6e3a1" },
}

local story_order = { "text", "badges", "structure", "padding", "columns", "composition", "tree" }

local function set_highlights()
	for group, spec in pairs(palette) do
		vim.api.nvim_set_hl(0, group, spec)
	end
end

local function story(title, document, opts)
	return vim.tbl_extend("force", {
		title = title,
		width = 76,
		height = math.max(8, #document),
		document = document,
	}, opts or {})
end

local stories = {}

stories.smoke = function()
	return story("Component smoke", {
		ui.section("Component smoke", { hl = "ComponentStorybookTitle" }),
		ui.line({
			ui.list({
				{ ui.badge("CR", { hl = "ComponentStorybookBadge" }), ui.text("open", "ComponentStorybookText") },
				{ ui.badge("ok", { hl = "ComponentStorybookBadge" }), ui.text("ready", "ComponentStorybookText") },
			}, { type = "horizontal", separator = ui.sep(nil, { hl = "ComponentStorybookSeparator" }) }),
		}),
		ui.divider(24, { hl = "ComponentStorybookSeparator" }),
		ui.text_line("Context row", "ComponentStorybookMuted"),
	}, { width = 50, height = 6 })
end

stories.text = function()
	return story("Text components", {
		ui.section("Text", { hl = "ComponentStorybookTitle" }),
		ui.text_line("text_line renders a whole highlighted row", "ComponentStorybookText"),
		ui.line({
			ui.text("Inline ", "ComponentStorybookText"),
			ui.text("spans", "ComponentStorybookAccent"),
			ui.text(" keep highlight ownership local to each fragment", "ComponentStorybookText"),
		}),
		ui.line({ ui.text("A line can carry row-level selection highlight") }, { hl = "ComponentStorybookSelection" }),
		ui.blank(),
		ui.text_line("blank() intentionally leaves an empty row above this line", "ComponentStorybookMuted"),
	})
end

stories.badges = function()
	return story("Badge components", {
		ui.section("Badges", { hl = "ComponentStorybookTitle" }),
		ui.line({
			ui.list({
				{ ui.badge("j/k", { hl = "ComponentStorybookBadge" }), ui.text("move", "ComponentStorybookText") },
				{ ui.badge("/", { hl = "ComponentStorybookBadge" }), ui.text("filter", "ComponentStorybookText") },
				{ ui.badge("CR", { hl = "ComponentStorybookBadge" }), ui.text("open", "ComponentStorybookText") },
			}, { type = "horizontal", separator = ui.sep(nil, { hl = "ComponentStorybookSeparator" }) }),
		}),
		ui.line({
			ui.list({
				{
					ui.badge("draft", { hl = "ComponentStorybookBadge" }),
					ui.text("local comment", "ComponentStorybookText"),
				},
				{
					ui.badge("stale", { hl = "ComponentStorybookWarning" }),
					ui.text("needs attention", "ComponentStorybookText"),
				},
			}, { type = "horizontal", separator = ui.sep(nil, { hl = "ComponentStorybookSeparator" }) }),
		}),
	})
end

stories.structure = function()
	return story("Structural components", {
		ui.section("Section heading", { hl = "ComponentStorybookTitle" }),
		ui.text_line("Rows can be mixed component lines and plain strings", "ComponentStorybookText"),
		ui.divider(56, { hl = "ComponentStorybookSeparator" }),
		ui.line({
			ui.text("Separators", "ComponentStorybookText"),
			ui.sep(nil, { hl = "ComponentStorybookSeparator" }),
			ui.text("create intentional rhythm", "ComponentStorybookText"),
		}),
		ui.blank(),
		ui.text_line("The blank row above is part of the document", "ComponentStorybookMuted"),
	})
end

stories.padding = function()
	return story("Padding and truncation components", {
		ui.section("Padding and truncation", { hl = "ComponentStorybookTitle" }),
		ui.line({
			ui.text("pad_left", "ComponentStorybookMuted"),
			ui.space(2),
			ui.pad_left(ui.text("42", "ComponentStorybookAccent"), 8),
			ui.text(" keeps numbers aligned", "ComponentStorybookText"),
		}),
		ui.line({
			ui.text("pad_right", "ComponentStorybookMuted"),
			ui.space(1),
			ui.pad_right(ui.text("ok", "ComponentStorybookState"), 8),
			ui.text("keeps labels aligned", "ComponentStorybookText"),
		}),
		ui.line({
			ui.text("truncate", "ComponentStorybookMuted"),
			ui.space(2),
			ui.truncate(ui.text("emoji 😀 and wide 漢字 keep display width", "ComponentStorybookWarning"), 34),
		}),
	})
end

stories.columns = function()
	return story("Column component", {
		ui.section("Columns", { hl = "ComponentStorybookTitle" }),
		ui.columns({
			{ ui.text("State", "ComponentStorybookMuted"), width = 10 },
			{ ui.text("Count", "ComponentStorybookMuted"), width = 7, align = "right" },
			{ ui.text("Message", "ComponentStorybookMuted"), width = 36 },
		}, { separator = " │ ", separator_hl = "ComponentStorybookSeparator" }),
		ui.columns({
			{ ui.text("open", "ComponentStorybookState"), width = 10 },
			{ ui.text("12", "ComponentStorybookAccent"), width = 7, align = "right" },
			{ ui.text("Fixed columns truncate long review summaries", "ComponentStorybookText"), width = 36 },
		}, { separator = " │ ", separator_hl = "ComponentStorybookSeparator" }),
		ui.columns({
			{ ui.text("resolved", "ComponentStorybookState"), width = 10 },
			{ ui.text("3", "ComponentStorybookAccent"), width = 7, align = "right" },
			{ ui.text("Short text pads to the configured width", "ComponentStorybookText"), width = 36 },
		}, { separator = " │ ", separator_hl = "ComponentStorybookSeparator" }),
	})
end

stories.composition = function()
	return story("Composed review row", {
		ui.section("Composed row", { hl = "ComponentStorybookTitle" }),
		ui.line({
			ui.text("› ", "ComponentStorybookAccent"),
			ui.list({
				{
					ui.badge("selected", { hl = "ComponentStorybookBadge" }),
					ui.columns({
						{ ui.text("src/app.lua", "ComponentStorybookText"), width = 18 },
						{ ui.text("resolved", "ComponentStorybookState"), width = 10 },
						{
							ui.text("Reusable rows compose inline with selection", "ComponentStorybookText"),
							width = 32,
						},
					}, { separator = " ", separator_hl = "ComponentStorybookSeparator" }),
				},
			}, { type = "horizontal", separator = false }),
		}, { hl = "ComponentStorybookSelection" }),
		ui.line({
			ui.text("  ", "ComponentStorybookMuted"),
			ui.list({
				{
					ui.badge("r", { hl = "ComponentStorybookBadge" }),
					ui.text("toggle state", "ComponentStorybookText"),
				},
				{
					ui.badge("p", { hl = "ComponentStorybookBadge" }),
					ui.text("preview thread", "ComponentStorybookText"),
				},
			}, { type = "horizontal", separator = ui.sep(nil, { hl = "ComponentStorybookSeparator" }) }),
		}),
	})
end

stories.tree = function()
	local nodes = {
		{
			kind = "file",
			id = "src/app.lua",
			expanded = true,
			children = {
				{ kind = "thread", id = "nil-guard", label = "selected thread: fix nil guard" },
				{ kind = "thread", id = "rename", label = "open thread: rename variable" },
			},
		},
		{
			kind = "file",
			id = "docs/readme.md",
			expanded = false,
			children = {
				{ kind = "thread", id = "hidden-docs", label = "hidden docs child" },
			},
		},
	}
	local tree_list = ui.tree(nodes, {
		selectable = true,
		selected_key = "nil-guard",
		selected_hl = "ComponentStorybookSelection",
		marker_hl = "ComponentStorybookAccent",
		key = function(node)
			return node.id
		end,
		expanded = function(node)
			return node.kind ~= "file" or node.expanded
		end,
		prefix = function(ctx)
			return string.rep("  ", ctx.depth or 0) .. ctx.marker .. " "
		end,
		render = function(node, ctx)
			if node.kind == "file" then
				return ui.line({
					ui.text(ctx.expanded and "▾" or "▸", "ComponentStorybookAccent"),
					ui.text(" " .. node.id, "ComponentStorybookText"),
				})
			end
			return ui.line({
				ui.text("● ", "ComponentStorybookState"),
				ui.text(node.label, "ComponentStorybookText"),
			})
		end,
	})
	return story("Tree component", {
		ui.section("Tree", { hl = "ComponentStorybookTitle" }),
		ui.text_line("Tree flattens expanded nodes and keeps collapsed parents selectable.", "ComponentStorybookMuted"),
		ui.divider(64, { hl = "ComponentStorybookSeparator" }),
		unpack(tree_list.document),
	}, { width = 72, height = 9 })
end

function M.story(name)
	local builder = stories[name or ""] or stories.text
	return builder()
end

function M.document()
	local document = {}
	for index, name in ipairs(story_order) do
		local current = M.story(name)
		if index > 1 then
			table.insert(document, ui.divider(64, { hl = "ComponentStorybookSeparator" }))
		end
		vim.list_extend(document, current.document)
	end
	return document
end

local function open_float(current, name)
	local ns = vim.api.nvim_create_namespace("component_storybook_" .. (name or "all"))
	local buf = vim.api.nvim_create_buf(false, true)
	renderer.render(buf, ns, current.document)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false

	local width = current.width
	local height = current.height
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.max(0, math.floor((vim.o.lines - height) / 2)),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " " .. current.title .. " ",
		title_pos = "center",
	})
	vim.wo[win].winhighlight = table.concat({
		"NormalFloat:ComponentStorybookNormal",
		"FloatBorder:ComponentStorybookBorder",
		"FloatTitle:ComponentStorybookTitle",
		"CursorLine:ComponentStorybookSelection",
	}, ",")
	vim.keymap.set("n", "q", function()
		pcall(vim.api.nvim_win_close, win, true)
	end, { buffer = buf, silent = true })
	return { buffer = buf, window = win }
end

function M.open(name)
	set_highlights()
	local current
	if name and name ~= "all" then
		current = M.story(name)
	else
		current = story("Components Storybook", M.document(), { width = 86, height = 22 })
	end
	return open_float(current, name)
end

return M
