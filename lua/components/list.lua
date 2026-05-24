local make = require("components.component").make
local blank_component = require("components.blank")
local line_component = require("components.line")
local text_component = require("components.text")

local M = {}

local function is_component(value)
	return type(value) == "table" and value._ur_component == true
end

local function text(value, hl)
	return text_component.component(value, hl)
end

local function line(children, opts)
	return line_component.component(children, opts)
end

local function blank()
	return blank_component.component()
end

local function clamp(value, min_value, max_value)
	return math.max(min_value, math.min(max_value, value))
end

local function copy_opts(opts)
	return vim.tbl_extend("force", {}, opts or {})
end

local function horizontal_opts(opts)
	local result = copy_opts(opts)
	result.type = "horizontal"
	result.direction = nil
	result.orientation = nil
	return result
end

local function horizontal(items, opts)
	return make("list", { items = items or {}, opts = horizontal_opts(opts or {}) })
end

local function direction_for(opts)
	return opts.direction or opts.orientation or opts.type or "vertical"
end

local function default_item_text(item)
	if is_component(item) or type(item) ~= "table" then
		return item
	end
	return tostring(item.label or item.text or item.value or item[1] or "")
end

local function as_document(value)
	if value == nil or value == false then
		return {}
	end
	if is_component(value) or type(value) ~= "table" then
		return { value }
	end
	return value
end

local function empty_document(empty, opts)
	if type(empty) == "function" then
		empty = empty(opts)
	end
	return as_document(empty)
end

local function selected_index(items, opts)
	if #items == 0 then
		return nil
	end
	return clamp(opts.selected or 1, 1, #items)
end

local function viewport(items, opts)
	if #items == 0 then
		return nil, nil, nil
	end
	local selected = selected_index(items, opts)
	local height = opts.height
	if not height or height <= 0 or height >= #items then
		return 1, #items, selected
	end
	if opts.first then
		local first = clamp(opts.first, 1, math.max(1, #items - height + 1))
		return first, math.min(#items, first + height - 1), selected
	end
	local first
	if opts.viewport == "top" then
		first = selected
	else
		first = selected - math.floor(height / 2)
	end
	first = clamp(first, 1, math.max(1, #items - height + 1))
	return first, math.min(#items, first + height - 1), selected
end

local function is_disabled(item, ctx, opts)
	if type(opts.disabled) == "function" then
		return opts.disabled(item, ctx) == true
	end
	if opts.disabled ~= nil then
		return opts.disabled == true
	end
	return type(item) == "table" and item.disabled == true
end

local function row_context(item, index, position, selected, opts)
	local ctx = {
		item = item,
		index = index,
		position = position,
		total = opts.total,
		selected = index == selected,
		truncate_width = opts.truncate_width,
	}
	ctx.disabled = is_disabled(item, ctx, opts)
	ctx.marker = ctx.selected and (opts.marker or "›") or (opts.unselected_marker or " ")
	if ctx.disabled and opts.disabled_marker then
		ctx.disabled_marker = opts.disabled_marker
	end
	if opts.prefix then
		ctx.prefix = opts.prefix(ctx)
	else
		ctx.prefix = ctx.marker ~= "" and (ctx.marker .. " ") or ""
	end
	return ctx
end

local function row_meta(item, ctx, opts)
	if type(opts.row) == "function" then
		return opts.row(item, ctx)
	end
	return {
		kind = "item",
		item = item,
		index = ctx.index,
		position = ctx.position,
		selected = ctx.selected,
		disabled = ctx.disabled,
	}
end

local function apply_row_options(row, ctx, opts)
	local row_opts = {}
	if opts.truncate_width then
		row_opts.truncate_width = opts.truncate_width
	end
	if ctx.disabled and opts.disabled_hl then
		row_opts.hl = opts.disabled_hl
	end
	if ctx.selected and opts.selected_hl then
		row_opts.hl = opts.selected_hl
	end
	if vim.tbl_isempty(row_opts) and not opts.selectable then
		return row
	end
	if opts.selectable and opts.marker ~= false then
		return line({ text(ctx.prefix, opts.marker_hl), row }, row_opts)
	end
	return line({ row }, row_opts)
end

local function render_item(item, ctx, opts)
	local rendered
	if type(opts.render) == "function" then
		rendered = opts.render(item, ctx)
	else
		rendered = default_item_text(item)
	end
	if rendered == nil or rendered == false then
		return nil
	end
	return apply_row_options(rendered, ctx, opts)
end

local function pad_document(document, height, pad_line)
	if not height then
		return document
	end
	while #document < height do
		table.insert(document, pad_line or "")
	end
	while #document > height do
		table.remove(document)
	end
	return document
end

local function vertical(items, opts)
	opts = opts or {}
	items = items or {}
	opts.total = #items
	local document = {}
	local rows = {}

	if #items == 0 then
		document = empty_document(opts.empty, opts)
		if opts.pad == true or (opts.pad == nil and opts.height ~= nil) then
			pad_document(document, opts.height, opts.pad_line or "")
		end
		return { document = document, rows = rows, first = nil, last = nil, selected = nil }
	end

	local first, last, selected = viewport(items, opts)
	for index = first, last do
		local item = items[index]
		local ctx = row_context(item, index, #document + 1, selected, opts)
		local rendered = render_item(item, ctx, opts)
		if rendered ~= nil then
			table.insert(document, rendered)
			local meta = row_meta(item, ctx, opts)
			if meta ~= nil then
				rows[#document] = meta
			end
		end
	end

	if opts.pad == true or (opts.pad == nil and opts.height ~= nil) then
		pad_document(document, opts.height, opts.pad_line or "")
	end

	return { document = document, rows = rows, first = first, last = last, selected = selected }
end

function M.list(items, opts)
	opts = opts or {}
	if direction_for(opts) == "horizontal" then
		return horizontal(items, opts)
	end
	return vertical(items, opts)
end

M.blank = blank

return M
