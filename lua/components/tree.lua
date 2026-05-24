local list = require("components.list")

local M = {}

local function copy_opts(opts)
	return vim.tbl_extend("force", {}, opts or {})
end

local function children_for(node, opts)
	if type(opts.children) == "function" then
		return opts.children(node) or {}
	end
	return node and node.children or {}
end

local function node_key(node, ctx, opts)
	if type(opts.key) == "function" then
		return opts.key(node, ctx)
	end
	return node and (node.key or node.id)
end

local function is_expanded(node, ctx, opts)
	if type(opts.expanded) == "function" then
		return opts.expanded(node, ctx) ~= false
	end
	if node and node.expanded ~= nil then
		return node.expanded == true
	end
	return true
end

local function flatten_into(entries, nodes, opts, depth, parent)
	for index, node in ipairs(nodes or {}) do
		local child_nodes = children_for(node, opts)
		local ctx = {
			node = node,
			index = index,
			depth = depth,
			parent = parent,
			has_children = #child_nodes > 0,
		}
		ctx.key = node_key(node, ctx, opts)
		ctx.expanded = ctx.has_children and is_expanded(node, ctx, opts) or false
		local entry = {
			node = node,
			key = ctx.key,
			depth = depth,
			parent = parent,
			index = index,
			has_children = ctx.has_children,
			expanded = ctx.expanded,
		}
		table.insert(entries, entry)
		if ctx.expanded then
			flatten_into(entries, child_nodes, opts, depth + 1, entry)
		end
	end
end

function M.flatten(nodes, opts)
	local entries = {}
	flatten_into(entries, nodes or {}, opts or {}, 0, nil)
	return entries
end

local function selected_index(entries, opts)
	if opts.selected then
		return opts.selected
	end
	if opts.selected_key ~= nil then
		for index, entry in ipairs(entries) do
			if entry.key == opts.selected_key then
				return index
			end
		end
	end
	return opts.default_selected
end

local function tree_context(entry, ctx)
	local result = vim.tbl_extend("force", {}, ctx or {})
	result.entry = entry
	result.node = entry.node
	result.key = entry.key
	result.depth = entry.depth
	result.parent = entry.parent
	result.has_children = entry.has_children
	result.expanded = entry.expanded
	return result
end

function M.list(nodes, opts)
	opts = opts or {}
	local entries = M.flatten(nodes, opts)
	local list_opts = copy_opts(opts)
	list_opts.selected = selected_index(entries, opts)
	list_opts.render = function(entry, ctx)
		if type(opts.render) == "function" then
			return opts.render(entry.node, tree_context(entry, ctx))
		end
		return entry.node
	end
	list_opts.row = function(entry, ctx)
		if type(opts.row) == "function" then
			return opts.row(entry.node, tree_context(entry, ctx))
		end
		return {
			kind = "tree",
			node = entry.node,
			key = entry.key,
			depth = entry.depth,
			selected = ctx.selected,
			disabled = ctx.disabled,
		}
	end
	if type(opts.prefix) == "function" then
		list_opts.prefix = function(ctx)
			return opts.prefix(tree_context(ctx.item, ctx))
		end
	end

	local result = list.list(entries, list_opts)
	result.entries = entries
	return result
end

return M
