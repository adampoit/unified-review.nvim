local make = require("components.component").make

local M = {}

local DEFAULT_SEPARATOR = " · "

local function is_list(value)
	return type(value) == "table"
		and value.label == nil
		and value.text == nil
		and value.action == nil
		and not value._ur_component
end

local function normalize_item(item)
	if type(item) == "table" then
		return {
			label = vim.trim(tostring(item.label or item[1] or "")),
			text = tostring(item.text or item.action or item[2] or ""),
		}
	end
	return { label = vim.trim(tostring(item or "")), text = "" }
end

local function render_badge(label)
	label = vim.trim(tostring(label or ""))
	return label ~= "" and (" " .. label .. " ") or ""
end

local function render_item(item)
	local normalized = normalize_item(item)
	local badge = render_badge(normalized.label)
	if normalized.text ~= "" then
		return badge .. normalized.text
	end
	return badge
end

local function render_line(items, opts)
	opts = opts or {}
	local parts = {}
	local separator = opts.separator or DEFAULT_SEPARATOR
	for _, item in ipairs(items or {}) do
		local text = render_item(item)
		if text ~= "" then
			table.insert(parts, text)
		end
	end
	return table.concat(parts, separator)
end

function M.component(label, opts)
	opts = opts or {}
	return make("badge", { label = label, hl = opts.hl })
end

function M.render(value, opts)
	return is_list(value) and render_line(value, opts) or render_item(value)
end

return M
