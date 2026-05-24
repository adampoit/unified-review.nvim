local badge = require("components.badge")
local blank = require("components.blank")
local columns = require("components.columns")
local divider = require("components.divider")
local inset = require("components.inset")
local line = require("components.line")
local list = require("components.list")
local pad_left = require("components.pad_left")
local pad_right = require("components.pad_right")
local section = require("components.section")
local sep = require("components.sep")
local space = require("components.space")
local text = require("components.text")
local text_line = require("components.text_line")
local tree = require("components.tree")
local truncate = require("components.truncate")

local M = {}

function M.text(value, hl)
	return text.component(value, hl)
end

function M.line(children, opts)
	return line.component(children, opts)
end

function M.text_line(value, hl)
	return text_line.component(value, hl)
end

function M.blank()
	return blank.component()
end

function M.badge(label, opts)
	return badge.component(label, opts)
end

function M.sep(value, opts)
	return sep.component(value, opts)
end

function M.divider(width, opts)
	return divider.component(width, opts)
end

function M.section(title, opts)
	return section.component(title, opts)
end

function M.space(width, opts)
	return space.component(width, opts)
end

function M.pad_left(child, width, opts)
	return pad_left.component(child, width, opts)
end

function M.pad_right(child, width, opts)
	return pad_right.component(child, width, opts)
end

function M.truncate(child, width, opts)
	return truncate.component(child, width, opts)
end

function M.columns(cells, opts)
	return columns.component(cells, opts)
end

function M.list(items, opts)
	return list.list(items, opts)
end

function M.tree(nodes, opts)
	return tree.list(nodes, opts)
end

function M.inset(document, opts)
	return inset.apply(document, opts)
end

M.renderer = require("components.renderer")
M.legacy_badge = badge.render
M.legacy_divider = divider.render

return M
