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

local function display_width(value)
	return vim.fn.strdisplaywidth(value or "")
end

local function fill_text(fill, width)
	fill = tostring(fill or " ")
	if fill == "" or width <= 0 then
		return ""
	end
	local value = ""
	while display_width(value) < width do
		value = value .. fill
	end
	return vim.fn.strcharpart(value, 0, width)
end

local function is_blank(value)
	return value == "" or (is_component(value) and value.kind == "blank")
end

local function copy_opts(opts)
	return vim.tbl_extend("force", {}, opts or {})
end

function M.apply(document, opts)
	opts = opts or {}
	local left = opts.left
	if left == nil then
		left = opts.width or 2
	end
	local padding = opts.text or fill_text(opts.fill or " ", math.max(0, left or 0))
	local preserve_blank = opts.preserve_blank ~= false
	local result = {}

	for _, entry in ipairs(document or {}) do
		if preserve_blank and is_blank(entry) then
			table.insert(result, "")
		else
			local line_opts = {}
			if is_component(entry) and entry.kind == "line" then
				line_opts = copy_opts(entry.opts)
			end
			if line_opts.truncate_width then
				line_opts.truncate_width = line_opts.truncate_width + display_width(padding)
			elseif opts.truncate_width then
				line_opts.truncate_width = opts.truncate_width
			end
			if opts.hl and not line_opts.hl then
				line_opts.hl = opts.hl
			end
			table.insert(result, line({ text(padding, opts.padding_hl), entry }, line_opts))
		end
	end

	return result
end

return M
