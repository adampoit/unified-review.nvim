local loader = require("components.loader")

local M = {}

local function is_component(value)
	return type(value) == "table" and value._ur_component == true
end

local function text_value(value)
	return tostring(value or "")
end

local function display_width(value)
	return vim.fn.strdisplaywidth(value or "")
end

local function prefix_for_display_width(value, width)
	value = text_value(value)
	if not width or width < 0 or display_width(value) <= width then
		return value
	end
	local text = ""
	local used = 0
	for index = 0, vim.fn.strchars(value) - 1 do
		local char = vim.fn.strcharpart(value, index, 1)
		local char_width = display_width(char)
		if used + char_width > width then
			break
		end
		text = text .. char
		used = used + char_width
	end
	return text
end

local function truncate(value, width)
	value = text_value(value)
	if not width or width < 0 or display_width(value) <= width then
		return value
	end
	if width <= 0 then
		return ""
	end
	return prefix_for_display_width(value, width - 1) .. "…"
end

local function byte_len(value)
	return #text_value(value)
end

local function byte_index_for_display_width(value, width)
	return #prefix_for_display_width(value, width)
end

local function add_span(spans, group, start_col, end_col)
	if not group or start_col == end_col then
		return
	end
	table.insert(spans, { group = group, start_col = start_col, end_col = end_col })
end

local function append_text(state, value, group)
	value = text_value(value)
	if value == "" then
		return
	end
	local start_col = byte_len(state.text)
	state.text = state.text .. value
	add_span(state.spans, group, start_col, byte_len(state.text))
end

local function append_fragment(state, fragment, group)
	if not fragment or fragment.text == "" then
		return
	end
	local start_col = byte_len(state.text)
	state.text = state.text .. fragment.text
	add_span(state.spans, group, start_col, byte_len(state.text))
	for _, span in ipairs(fragment.spans or {}) do
		add_span(state.spans, span.group, start_col + span.start_col, start_col + span.end_col)
	end
end

local function badge_text(label)
	label = vim.trim(text_value(label))
	return label ~= "" and (" " .. label .. " ") or ""
end

local function fill_text(fill, width)
	fill = text_value(fill or " ")
	if fill == "" or width <= 0 then
		return ""
	end
	local text = ""
	while display_width(text) < width do
		text = text .. fill
	end
	return prefix_for_display_width(text, width)
end

local function clamp_spans(spans, max_col)
	local clamped = {}
	for _, span in ipairs(spans or {}) do
		local start_col = math.min(span.start_col, max_col)
		local end_col = math.min(span.end_col, max_col)
		if span.group and start_col < end_col then
			table.insert(clamped, {
				group = span.group,
				start_col = start_col,
				end_col = end_col,
			})
		end
	end
	return clamped
end

local function truncate_fragment(fragment, width)
	if not width or width < 0 or display_width(fragment.text) <= width then
		return fragment
	end
	local max_col = byte_index_for_display_width(fragment.text, math.max(0, width - 1))
	return {
		text = truncate(fragment.text, width),
		spans = clamp_spans(fragment.spans, max_col),
	}
end

local flatten_inline
local flatten_fragment

local function flatten_children(children, state, opts)
	for _, child in ipairs(children or {}) do
		flatten_inline(child, state, opts)
	end
end

flatten_fragment = function(node, opts)
	local state = { text = "", spans = {} }
	flatten_inline(node, state, opts or {})
	return state
end

local function padded_fragment(node, width, side, fill, opts)
	local fragment = flatten_fragment(node, opts)
	local padding = fill_text(fill, math.max(0, (width or 0) - display_width(fragment.text)))
	if padding == "" then
		return fragment
	end
	if side == "left" then
		local shifted = {}
		for _, span in ipairs(fragment.spans) do
			table.insert(shifted, {
				group = span.group,
				start_col = #padding + span.start_col,
				end_col = #padding + span.end_col,
			})
		end
		return { text = padding .. fragment.text, spans = shifted }
	end
	return { text = fragment.text .. padding, spans = fragment.spans }
end

local function normalize_cell(cell)
	if is_component(cell) or type(cell) ~= "table" then
		return { child = cell }
	end
	if cell.child ~= nil then
		return cell
	end
	return vim.tbl_extend("force", cell, { child = cell[1] })
end

local function align_fragment(fragment, width, align, fill)
	width = width or 0
	local padding_width = math.max(0, width - display_width(fragment.text))
	if padding_width == 0 then
		return fragment
	end
	if align == "right" then
		local padding = fill_text(fill, padding_width)
		local shifted = {}
		for _, span in ipairs(fragment.spans) do
			table.insert(shifted, {
				group = span.group,
				start_col = #padding + span.start_col,
				end_col = #padding + span.end_col,
			})
		end
		return { text = padding .. fragment.text, spans = shifted }
	elseif align == "center" then
		local left_width = math.floor(padding_width / 2)
		local left = fill_text(fill, left_width)
		local right = fill_text(fill, padding_width - left_width)
		local shifted = {}
		for _, span in ipairs(fragment.spans) do
			table.insert(shifted, {
				group = span.group,
				start_col = #left + span.start_col,
				end_col = #left + span.end_col,
			})
		end
		return { text = left .. fragment.text .. right, spans = shifted }
	end
	return { text = fragment.text .. fill_text(fill, padding_width), spans = fragment.spans }
end

local function flatten_columns(node, state, opts)
	local column_opts = vim.tbl_extend("force", opts, node.opts or {})
	local separator = column_opts.separator
	if separator == nil then
		separator = string.rep(" ", column_opts.gap or 2)
	end
	for index, raw_cell in ipairs(node.cells or {}) do
		if index > 1 then
			append_text(state, separator, column_opts.separator_hl)
		end
		local cell = normalize_cell(raw_cell)
		local fragment = flatten_fragment(cell.child, vim.tbl_extend("force", column_opts, cell.opts or {}))
		local target_width = cell.width or cell.max_width
		if target_width and cell.truncate ~= false then
			fragment = truncate_fragment(fragment, target_width)
		end
		fragment = align_fragment(fragment, cell.width or cell.min_width, cell.align, cell.fill or column_opts.fill)
		append_fragment(state, fragment, cell.hl)
	end
end

local function normalize_horizontal_item(item)
	if is_component(item) or type(item) ~= "table" then
		return { children = { item } }
	end
	if item.child ~= nil then
		return vim.tbl_extend("force", item, { children = { item.child } })
	end
	if item.children ~= nil then
		return item
	end
	return { children = item }
end

local function horizontal_item_fragment(item, horizontal_opts)
	local normalized = normalize_horizontal_item(item)
	local item_opts = vim.tbl_extend("force", horizontal_opts, normalized.opts or {})
	local gap_width = normalized.gap
	if gap_width == nil then
		gap_width = item_opts.item_gap
	end
	local gap = fill_text(" ", math.max(0, gap_width == nil and 1 or gap_width))
	local state = { text = "", spans = {} }
	local appended = false
	for _, child in ipairs(normalized.children or {}) do
		local fragment = flatten_fragment(child, item_opts)
		if fragment.text ~= "" then
			if appended then
				append_text(state, gap, item_opts.gap_hl)
			end
			append_fragment(state, fragment)
			appended = true
		end
	end
	if normalized.hl then
		local spans = { { group = normalized.hl, start_col = 0, end_col = #state.text } }
		vim.list_extend(spans, state.spans)
		return { text = state.text, spans = spans }
	end
	return state
end

local function append_horizontal_separator(state, horizontal_opts)
	local separator = horizontal_opts.separator
	if separator == false then
		return
	end
	if separator == nil then
		separator = " · "
	end
	if is_component(separator) then
		append_fragment(state, flatten_fragment(separator, horizontal_opts))
	else
		append_text(state, separator, horizontal_opts.separator_hl)
	end
end

local function flatten_horizontal(node, state, opts)
	local horizontal_opts = vim.tbl_extend("force", opts, node.opts or {})
	local appended = false
	for _, item in ipairs(node.items or {}) do
		local fragment = horizontal_item_fragment(item, horizontal_opts)
		if fragment.text ~= "" then
			if appended then
				append_horizontal_separator(state, horizontal_opts)
			end
			append_fragment(state, fragment)
			appended = true
		end
	end
end

flatten_inline = function(node, state, opts)
	if node == nil or node == false then
		return
	end
	if type(node) == "string" or type(node) == "number" then
		append_text(state, node)
		return
	end
	if not is_component(node) then
		append_text(state, node)
		return
	end
	if node.kind == "text" then
		append_text(state, node.value, node.hl)
	elseif node.kind == "badge" then
		append_text(state, badge_text(node.label), node.hl or opts.badge_hl)
	elseif node.kind == "sep" then
		append_text(state, node.value or " · ", node.hl or opts.separator_hl)
	elseif node.kind == "divider" then
		append_text(
			state,
			string.rep("─", math.max(8, node.width or opts.divider_width or 8)),
			node.hl or opts.divider_hl
		)
	elseif node.kind == "section" then
		append_text(state, node.title, node.hl or opts.section_hl)
	elseif node.kind == "space" then
		append_text(state, fill_text(" ", math.max(0, node.width or 1)), node.hl)
	elseif node.kind == "pad_left" then
		append_fragment(state, padded_fragment(node.child, node.width, "left", node.fill, opts), node.hl)
	elseif node.kind == "pad_right" then
		append_fragment(state, padded_fragment(node.child, node.width, "right", node.fill, opts), node.hl)
	elseif node.kind == "truncate" then
		append_fragment(state, truncate_fragment(flatten_fragment(node.child, opts), node.width), node.hl)
	elseif node.kind == "columns" then
		flatten_columns(node, state, opts)
	elseif node.kind == "list" and ((node.opts or {}).type == "horizontal") then
		flatten_horizontal(node, state, opts)
	elseif node.kind == "line" then
		flatten_children(node.children, state, vim.tbl_extend("force", opts, node.opts or {}))
	elseif node.kind == "text_line" then
		append_text(state, node.value, node.hl)
	elseif node.kind == "loader" then
		local spinner = loader.spinner(node.frame or opts.loader_frame, node.frames or opts.loader_frames)
		local separator = node.separator == nil and " " or node.separator
		if node.position == "suffix" then
			append_text(state, node.label, node.hl)
			append_text(state, separator)
			append_text(state, spinner, node.spinner_hl or node.hl)
		else
			append_text(state, spinner, node.spinner_hl or node.hl)
			append_text(state, separator)
			append_text(state, node.label, node.hl)
		end
	elseif node.kind == "blank" then
		return
	else
		append_text(state, node.value or "")
	end
end

function M.is_component(value)
	return is_component(value)
end

function M.flatten_line(line, opts)
	opts = opts or {}
	local state = { text = "", spans = {} }
	if line == nil or line == false then
		return { text = "", spans = {} }
	end
	if is_component(line) then
		if line.kind == "blank" then
			return { text = "", spans = {} }
		elseif line.kind == "line" then
			flatten_children(line.children, state, vim.tbl_extend("force", opts, line.opts or {}))
		else
			flatten_inline(line, state, opts)
		end
	else
		append_text(state, line)
	end

	local line_opts = is_component(line) and line.opts or nil
	local truncate_width = (line_opts and line_opts.truncate_width) or opts.truncate_width
	if truncate_width then
		state = truncate_fragment(state, truncate_width)
	end
	if line_opts and line_opts.hl and state.text ~= "" then
		table.insert(state.spans, 1, { group = line_opts.hl, start_col = 0, end_col = #state.text })
	end
	return state
end

function M.flatten(document, opts)
	local lines = {}
	local highlights = {}
	for index, line in ipairs(document or {}) do
		local flattened = M.flatten_line(line, opts)
		table.insert(lines, flattened.text)
		for _, span in ipairs(flattened.spans or {}) do
			table.insert(highlights, {
				lnum = index - 1,
				group = span.group,
				start_col = span.start_col,
				end_col = span.end_col,
			})
		end
	end
	return { lines = lines, highlights = highlights }
end

function M.lines(document, opts)
	return M.flatten(document, opts).lines
end

function M.apply_highlights(buf, ns, highlights)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	for _, hl in ipairs(highlights or {}) do
		pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl.group, hl.lnum, hl.start_col or 0, hl.end_col or -1)
	end
end

function M.render(buf, ns, document, opts)
	opts = opts or {}
	local flattened = M.flatten(document, opts)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return flattened
	end
	if opts.clear ~= false then
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, flattened.lines)
	M.apply_highlights(buf, ns, flattened.highlights)
	return flattened
end

return M
