--- Project-wide review overview buffer.
local float = require("unified_review.ui.float")
local ui = require("components")
local renderer = require("components.renderer")
local selection = require("unified_review.session.selection")
local state = require("unified_review.session.state")
local threads = require("unified_review.ui.thread_query")
local tree = require("components.tree")

local M = {}

M.ns = vim.api.nvim_create_namespace("unified_review_thread_panel")
M.compose_ns = vim.api.nvim_create_namespace("unified_review_thread_panel_composer")

local HIGHLIGHT_LINKS = {
	UnifiedReviewThreadsTitle = "UnifiedReviewFloatTitle",
	UnifiedReviewThreadsContext = "UnifiedReviewFloatContext",
	UnifiedReviewThreadsBadge = "UnifiedReviewFloatBadge",
	UnifiedReviewThreadsBorder = "UnifiedReviewFloatBorder",
	UnifiedReviewThreadsFooter = "UnifiedReviewFloatFooter",
	UnifiedReviewThreadsSelection = "UnifiedReviewFloatSelection",
	UnifiedReviewThreadsSeparator = "UnifiedReviewFloatSeparator",
	UnifiedReviewThreadsWarning = "UnifiedReviewFloatWarning",
	UnifiedReviewThreadsOpen = "DiagnosticInfo",
	UnifiedReviewThreadsResolved = "DiagnosticOk",
	UnifiedReviewThreadsDraft = "String",
	UnifiedReviewThreadsStale = "WarningMsg",
	UnifiedReviewThreadsFile = "Directory",
	UnifiedReviewThreadsAuthor = "Identifier",
	UnifiedReviewThreadsKey = "UnifiedReviewFloatKey",
	UnifiedReviewThreadsSection = "UnifiedReviewFloatSection",
	UnifiedReviewThreadsMuted = "UnifiedReviewFloatMuted",
}

local STATE_ICONS = threads.STATE_ICONS
local FILTER_STATES = threads.FILTER_STATES

local function clamp(value, min_value, max_value)
	return math.max(min_value, math.min(max_value, value))
end

local function ensure_highlights()
	float.ensure_highlights(HIGHLIGHT_LINKS)
end

local HORIZONTAL_PADDING = "  "
local OVERVIEW_KEY_ITEMS = {
	{ label = "j/k", text = "select" },
	{ label = "o/v/d/s/a", text = "states" },
	{ label = "/", text = "filter" },
	{ label = "S", text = "scope" },
	{ label = "CR", text = "jump" },
	{ label = "Space/za", text = "collapse" },
	{ label = "R", text = "reply inline" },
	{ label = "e", text = "export" },
	{ label = "P", text = "publish drafts" },
	{ label = "D", text = "delete" },
	{ label = "Esc", text = "cancel reply" },
	{ label = "q", text = "close" },
}

local function style_lines(lines)
	return ui.inset(lines, { text = HORIZONTAL_PADDING })
end

local function key_hint_line(items)
	local hints = {}
	for _, item in ipairs(items or {}) do
		table.insert(hints, {
			ui.badge(item.label, { hl = "UnifiedReviewThreadsKey" }),
			item.text and item.text ~= "" and ui.text(item.text) or nil,
		})
	end
	return ui.line({
		ui.list(hints, {
			type = "horizontal",
			separator = ui.sep(nil, { hl = "UnifiedReviewThreadsSeparator" }),
		}),
	}, { hl = "UnifiedReviewThreadsFooter" })
end

local function context_line(value)
	return ui.text_line(value, "UnifiedReviewThreadsContext")
end

local function section_line(value)
	return ui.section(value, { hl = "UnifiedReviewThreadsSection" })
end

local function warning_line(value)
	return ui.text_line(value, "UnifiedReviewThreadsWarning")
end

local function divider_line(width)
	return ui.divider(width, { hl = "UnifiedReviewThreadsSeparator" })
end

local function state_highlight_name(state_name)
	if state_name == "stale" then
		return "UnifiedReviewThreadsStale"
	end
	if state_name == "draft" then
		return "UnifiedReviewThreadsDraft"
	end
	if state_name == "resolved" then
		return "UnifiedReviewThreadsResolved"
	end
	return "UnifiedReviewThreadsOpen"
end

local function label_value_line(label, value)
	return ui.line({
		ui.text(label, "UnifiedReviewThreadsContext"),
		ui.text(" " .. tostring(value or ""), "UnifiedReviewThreadsContext"),
	})
end

local function plural(count, singular, plural_word)
	return string.format("%d %s", count, count == 1 and singular or (plural_word or (singular .. "s")))
end

local function thread_state(thread)
	return threads.thread_state(thread)
end

local function thread_state_label(thread)
	return threads.thread_state_label(thread)
end

local function preview_text(comment)
	return threads.preview_text(comment)
end

local function truncate(text, width)
	return threads.truncate(text, width)
end

local function target_label(th_target)
	return threads.target_label(th_target)
end

local function filter_for(session)
	return threads.filter_for(session)
end

local function collapsed_files_for(session)
	session._thread_file_collapsed = session._thread_file_collapsed or {}
	return session._thread_file_collapsed
end

local function status_line(session, visible_count)
	local summary = threads.summary(session)
	local draft_label = plural(summary.draft, "draft")
	if summary.local_draft and summary.remote_draft and (summary.local_draft > 0 or summary.remote_draft > 0) then
		draft_label =
			string.format("%s (%d local, %d remote)", draft_label, summary.local_draft or 0, summary.remote_draft or 0)
	end
	return string.format(
		"Status: %s · %s · %s · %s · %s · %s",
		plural(summary.threads, "thread"),
		plural(summary.open, "open"),
		draft_label,
		plural(summary.resolved, "resolved"),
		plural(summary.stale, "stale"),
		plural(visible_count, "visible")
	)
end

local function states_label(session)
	local filter = filter_for(session)
	local enabled = {}
	for _, state_name in ipairs(FILTER_STATES) do
		if filter[state_name] then
			table.insert(enabled, string.format("%s %s", STATE_ICONS[state_name], state_name))
		end
	end
	return #enabled > 0 and table.concat(enabled, ", ") or "none"
end

local function filter_summary_line(session)
	local visible = threads.filtered_threads(session)
	local scope = threads.scope_for(session)
	local query = session._thread_query and vim.trim(session._thread_query) or ""
	return string.format(
		"Threads: %d/%d    Scope: %s    States: %s    Query: %s",
		#visible,
		#(session.threads or {}),
		scope == "current" and "current file" or "project",
		states_label(session),
		query ~= "" and query or "none"
	)
end

function M.render_filter_lines(session)
	return {
		filter_summary_line(session),
		renderer.flatten_line(key_hint_line(OVERVIEW_KEY_ITEMS)).text,
	}
end

local function file_counts(group)
	local counts = { open = 0, resolved = 0, draft = 0, stale = 0 }
	for _, thread in ipairs(group.threads or {}) do
		local st = thread_state(thread)
		counts[st] = (counts[st] or 0) + 1
	end
	local parts = {}
	for _, st in ipairs(FILTER_STATES) do
		if counts[st] and counts[st] > 0 then
			table.insert(parts, string.format("%d %s", counts[st], st))
		end
	end
	return #parts > 0 and table.concat(parts, " · ") or "no visible threads"
end

local function attention_lines(session)
	local summary = threads.summary(session)
	local lines = {}
	if summary.draft > 0 or summary.stale > 0 or summary.open > 0 then
		table.insert(lines, warning_line("Needs attention"))
		if summary.draft > 0 then
			table.insert(lines, warning_line(string.format("  %s", plural(summary.draft, "draft thread"))))
			if (summary.local_draft or 0) > 0 then
				table.insert(
					lines,
					warning_line(string.format("  %s", plural(summary.local_draft, "local draft thread")))
				)
			end
			if (summary.remote_draft or 0) > 0 then
				table.insert(
					lines,
					warning_line(string.format("  %s", plural(summary.remote_draft, "remote draft thread")))
				)
			end
			if session.kind == "github_pr" and (summary.local_draft or 0) > 0 then
				table.insert(lines, warning_line("  Press P to publish exported drafts to a GitHub pending review"))
			end
		end
		if summary.stale > 0 then
			table.insert(lines, warning_line(string.format("  %s", plural(summary.stale, "stale/outdated thread"))))
		end
		if summary.open > 0 then
			table.insert(lines, warning_line(string.format("  %s", plural(summary.open, "unresolved open thread"))))
		end
	end
	return lines
end

local function content_width_for(session)
	local ui_state = session and session.ui or {}
	local win = ui_state.thread_panel_win
	local width
	if win and vim.api.nvim_win_is_valid(win) then
		width = vim.api.nvim_win_get_width(win)
	else
		local max_width = math.max(1, vim.o.columns - 4)
		width = clamp(math.floor(vim.o.columns * 0.78), math.min(64, max_width), max_width)
	end
	return math.max(32, width - vim.fn.strdisplaywidth(HORIZONTAL_PADDING) * 2)
end

local function list_preview_width(content_width)
	return clamp(math.floor(content_width * 0.42), 44, math.max(44, math.min(76, content_width - 48)))
end

local function display_width(value)
	return vim.fn.strdisplaywidth(value or "")
end

local function fill_text(fill, width)
	fill = tostring(fill or " ")
	if fill == "" or width <= 0 then
		return ""
	end
	local text = ""
	while display_width(text) < width do
		text = text .. fill
	end
	return vim.fn.strcharpart(text, 0, width)
end

local function pane_border(title, width, top)
	local left = top and "┌" or "└"
	local right = top and "┐" or "┘"
	local label = top and title and title ~= "" and (" " .. title .. " ") or ""
	local remaining = math.max(0, width - display_width(left) - display_width(right) - display_width(label))
	return ui.line({
		ui.text(left, "UnifiedReviewThreadsBorder"),
		ui.text(label, "UnifiedReviewThreadsTitle"),
		ui.text(fill_text("─", remaining), "UnifiedReviewThreadsBorder"),
		ui.text(right, "UnifiedReviewThreadsBorder"),
	})
end

local function pane_line(child, width)
	local inner_width = math.max(1, width - 4)
	return ui.line({
		ui.text("│ ", "UnifiedReviewThreadsBorder"),
		ui.pad_right(ui.truncate(child or "", inner_width), inner_width),
		ui.text(" │", "UnifiedReviewThreadsBorder"),
	})
end

local function boxed_pane(title, content, width, height)
	local lines = { pane_border(title, width, true) }
	local body_height = math.max(1, (height or #(content or {})) - 2)
	for index = 1, body_height do
		table.insert(lines, pane_line((content or {})[index] or "", width))
	end
	table.insert(lines, pane_border(nil, width, false))
	return lines
end

local function item_key(item)
	if not item then
		return nil
	end
	if item.kind == "file" then
		return item.path and ("file:" .. item.path) or nil
	end
	if item.kind == "thread" and item.thread then
		return item.thread.id and ("thread:" .. item.thread.id) or nil
	end
	return nil
end

local function set_selected_item(session, item)
	local key = item_key(item)
	if not key then
		return
	end
	session._thread_selected_key = key
	if item.kind == "thread" and item.thread then
		session._thread_selected_id = item.thread.id
	else
		session._thread_selected_id = nil
	end
end

local function build_thread_nodes(session, visible)
	local collapsed = collapsed_files_for(session)
	local groups = threads.group_by_file(session, visible)
	local nodes = {}
	for _, group in ipairs(groups) do
		local children = {}
		for _, thread in ipairs(group.threads) do
			table.insert(children, { kind = "thread", thread = thread })
		end
		table.insert(nodes, {
			kind = "file",
			path = group.path,
			collapsed = collapsed[group.path] == true,
			thread_count = #group.threads,
			counts = file_counts(group),
			children = children,
		})
	end
	return nodes
end

local function thread_tree_entries(session, visible)
	return tree.flatten(build_thread_nodes(session, visible), {
		key = item_key,
		expanded = function(item)
			return item.kind ~= "file" or not item.collapsed
		end,
	})
end

local function find_thread_parent(nodes, thread_id)
	if not thread_id then
		return nil
	end
	for _, node in ipairs(nodes or {}) do
		for _, child in ipairs(node.children or {}) do
			if child.thread and child.thread.id == thread_id then
				return node
			end
		end
	end
	return nil
end

local function selected_list_item(session, visible)
	local nodes = build_thread_nodes(session, visible)
	local entries = tree.flatten(nodes, {
		key = item_key,
		expanded = function(item)
			return item.kind ~= "file" or not item.collapsed
		end,
	})
	if #entries == 0 then
		return nil, nil, entries
	end
	local selected_key = session._thread_selected_key
	if not selected_key and session._thread_selected_id then
		selected_key = "thread:" .. session._thread_selected_id
	end
	for index, entry in ipairs(entries) do
		if entry.key == selected_key then
			set_selected_item(session, entry.node)
			return entry.node, index, entries
		end
	end
	local hidden_parent = find_thread_parent(nodes, session._thread_selected_id)
	if hidden_parent then
		for index, entry in ipairs(entries) do
			if entry.node == hidden_parent then
				set_selected_item(session, entry.node)
				return entry.node, index, entries
			end
		end
	end
	for index, entry in ipairs(entries) do
		if entry.node.kind == "thread" then
			set_selected_item(session, entry.node)
			return entry.node, index, entries
		end
	end
	set_selected_item(session, entries[1].node)
	return entries[1].node, 1, entries
end

local function build_thread_list(session, visible, selected, content_width)
	local nodes = build_thread_nodes(session, visible)
	local body_width = math.max(24, (content_width or 78) - 34)
	local height = session._thread_panel_pane_height and math.max(1, session._thread_panel_pane_height - 2) or nil
	local list = tree.list(nodes, {
		selectable = true,
		height = height,
		selected_key = item_key(selected),
		key = item_key,
		expanded = function(item)
			return item.kind ~= "file" or not item.collapsed
		end,
		selected_hl = "UnifiedReviewThreadsSelection",
		truncate_width = content_width,
		marker_hl = "UnifiedReviewThreadsSelection",
		prefix = function(ctx)
			return string.rep("  ", ctx.depth or 0) .. ctx.marker .. " "
		end,
		row = function(item, ctx)
			return {
				kind = item.kind,
				path = item.path or (item.thread and item.thread.target and item.thread.target.path),
				thread = item.thread,
				key = item_key(item),
				depth = ctx.depth,
				selected = ctx.selected,
			}
		end,
		render = function(item)
			if item.kind == "file" then
				return ui.line({
					ui.text(item.collapsed and "▸" or "▾", "UnifiedReviewThreadsFile"),
					ui.text(" " .. item.path .. "  ", "UnifiedReviewThreadsFile"),
					ui.text(plural(item.thread_count, "thread") .. "  ·  " .. item.counts, "UnifiedReviewThreadsFile"),
				}, { hl = "UnifiedReviewThreadsFile" })
			end
			local thread = item.thread or {}
			local th_target = thread.target or {}
			local st = thread_state(thread)
			local state_hl = state_highlight_name(st)
			local icon = STATE_ICONS[st] or "●"
			local state_label = thread_state_label(thread)
			local state_width = st == "draft" and 12 or 9
			local export_icon = threads.export_icon(thread)
			local first = thread.comments and thread.comments[1]
			local author = first and (first.author or "local") or ""
			local body = truncate(preview_text(first), body_width)
			local comment_count = #(thread.comments or {})
			local suffix = comment_count > 1 and string.format("  +%d replies", comment_count - 1) or ""
			return ui.line({
				ui.text(icon, state_hl),
				ui.text(" "),
				ui.text(export_icon, "UnifiedReviewThreadsBadge"),
				ui.text(" "),
				ui.text(string.format("%-" .. state_width .. "s", state_label), state_hl),
				ui.text(string.format(" %-8s %-12s %s%s", target_label(th_target), author, body, suffix)),
			})
		end,
	})
	return list.document, list.rows
end

local function detail_document(item, width, opts)
	opts = opts or {}
	if item and item.kind == "file" then
		local lines = opts.title == false and {} or { section_line("Selected file") }
		table.insert(lines, label_value_line("File:", item.path))
		table.insert(lines, label_value_line("Threads:", plural(item.thread_count, "thread") .. " · " .. item.counts))
		table.insert(lines, label_value_line("State:", item.collapsed and "collapsed" or "expanded"))
		table.insert(lines, "")
		table.insert(lines, context_line("Press Space/za or Enter to collapse/expand."))
		return lines
	end

	local thread = item and item.thread or item
	local lines = opts.title == false and {} or { section_line("Selected thread") }
	if not thread then
		table.insert(lines, warning_line("No thread selected"))
		return lines
	end
	local max_width = math.max(24, (width or 78) - 2)
	for _, line in ipairs(M.render_thread_document(thread)) do
		if type(line) == "string" then
			table.insert(lines, truncate(line, max_width))
		else
			table.insert(lines, line)
		end
	end
	return lines
end

local function append_composer(lines, session, selected, meta, content_width)
	local composer = session._thread_composer
	if not composer then
		return
	end
	if not selected or selected.id ~= composer.thread_id then
		session._thread_composer = nil
		return
	end
	local body = composer.lines or { "" }
	if #body == 0 then
		body = { "" }
	end
	table.insert(lines, "")
	table.insert(lines, divider_line(content_width or 78))
	table.insert(lines, section_line("Reply"))
	table.insert(lines, context_line("Edit below in this panel. <C-s> saves, Esc cancels, q closes the panel."))
	meta.composer = { start_row = #lines + 1 }
	for _, line in ipairs(body) do
		table.insert(lines, line)
	end
	meta.composer.footer_row = #lines + 1
	table.insert(lines, context_line("[<C-s>] save reply · [Esc] cancel reply"))
end

local function append_thread_workspace(lines, row_map, session, visible, selected, content_width)
	local list_lines, local_row_map = build_thread_list(session, visible, selected, content_width)
	local use_columns = content_width >= 96
	local detail_lines = detail_document(selected, content_width, { title = not use_columns })
	local base = #lines
	if use_columns then
		local list_width = list_preview_width(content_width)
		local detail_width = math.max(42, content_width - list_width - 2)
		local pane_height = session._thread_panel_pane_height or math.max(#list_lines, #detail_lines) + 2
		local list_box = boxed_pane("Threads", list_lines, list_width, pane_height)
		local detail_box = boxed_pane("Details", detail_lines, detail_width, pane_height)
		local count = math.max(#list_box, #detail_box)
		for index = 1, count do
			table.insert(
				lines,
				ui.columns({
					{ child = list_box[index] or "", width = list_width, truncate = false },
					{ child = detail_box[index] or "", width = detail_width, truncate = false },
				}, { separator = "  " })
			)
			local content_index = index - 1
			if local_row_map[content_index] then
				row_map[base + index] = local_row_map[content_index]
			end
		end
		return
	end
	for index, line in ipairs(list_lines) do
		table.insert(lines, line)
		if local_row_map[index] then
			row_map[#lines] = local_row_map[index]
		end
	end
	table.insert(lines, "")
	table.insert(lines, divider_line(content_width or 78))
	vim.list_extend(lines, detail_lines)
end

local function build_lines(session)
	local visible = threads.filtered_threads(session)
	local selected = selected_list_item(session, visible)
	local selected_thread_item = selected and selected.kind == "thread" and selected.thread or nil
	local summary = threads.summary(session)
	local content_width = content_width_for(session)
	local divider_width = math.min(100, content_width)
	local lines = {
		key_hint_line(OVERVIEW_KEY_ITEMS),
		"",
		context_line(filter_summary_line(session)),
		context_line(status_line(session, #visible)),
		context_line(
			string.format(
				"Files: %s · %s",
				plural(summary.files, "changed file"),
				plural(summary.files_with_threads, "file with comments", "files with comments")
			)
		),
		"",
		divider_line(divider_width),
		section_line("Summary"),
		string.format(
			"%s visible · %s total · %s",
			plural(#visible, "thread"),
			plural(summary.threads, "thread"),
			plural(summary.files_with_threads, "file with comments", "files with comments")
		),
		string.format(
			"%s · %s · %s · %s",
			plural(summary.open, "open"),
			plural(summary.draft, "draft"),
			plural(summary.resolved, "resolved"),
			plural(summary.stale, "stale")
		),
	}
	local attention = attention_lines(session)
	if #attention > 0 then
		table.insert(lines, "")
		vim.list_extend(lines, attention)
	end
	local row_map = {}
	local meta = {}
	if #visible == 0 then
		table.insert(lines, "")
		table.insert(lines, section_line("Threads"))
		local message = #(session.threads or {}) == 0 and "No review threads" or "No threads match the active filters"
		table.insert(lines, message)
		return lines, row_map, visible, meta
	end

	table.insert(lines, "")
	if content_width < 96 then
		table.insert(lines, divider_line(divider_width))
		table.insert(lines, section_line("Threads"))
	end
	local total_height = session.ui
			and session.ui.thread_panel_win
			and vim.api.nvim_win_is_valid(session.ui.thread_panel_win)
			and vim.api.nvim_win_get_height(session.ui.thread_panel_win)
		or clamp(
			math.floor(vim.o.lines * 0.78),
			math.min(18, math.max(1, vim.o.lines - 4)),
			math.max(1, vim.o.lines - 4)
		)
	session._thread_panel_pane_height = math.max(8, total_height - #lines - (session._thread_composer and 6 or 1))
	append_thread_workspace(lines, row_map, session, visible, selected, content_width)
	append_composer(lines, session, selected_thread_item, meta, divider_width)
	session._thread_panel_pane_height = nil
	return lines, row_map, visible, meta
end

--- Render lines for the project-wide review overview buffer.
function M.render_document(session)
	local lines = build_lines(session)
	return style_lines(lines)
end

function M.render_lines(session)
	return renderer.lines(M.render_document(session))
end

function M.render_thread_document(thread)
	if not thread then
		return { warning_line("No thread selected") }
	end
	local th_target = thread.target or {}
	local st = thread_state(thread)
	local state_hl = state_highlight_name(st)
	local lines = {
		ui.line({
			ui.text(STATE_ICONS[st] or "●", state_hl),
			ui.text(" " .. thread_state_label(thread), state_hl),
			ui.text(
				"  " .. (threads.export_icon(thread) == " " and "not exported" or "marked for export"),
				"UnifiedReviewThreadsBadge"
			),
		}, { hl = state_hl }),
		label_value_line("Target:", target_label(th_target)),
	}
	if th_target.path then
		table.insert(lines, label_value_line("File:", th_target.path))
	end
	if thread.is_outdated then
		table.insert(lines, warning_line("Warning: thread target is outdated"))
	end
	if thread.id then
		table.insert(lines, label_value_line("ID:", thread.id))
	end
	if not thread.comments or #thread.comments == 0 then
		table.insert(lines, "")
		table.insert(lines, "No comments")
		return lines
	end
	for i, comment in ipairs(thread.comments) do
		table.insert(lines, "")
		table.insert(
			lines,
			ui.text_line(string.format("Comment %d · %s", i, comment.author or "local"), "UnifiedReviewThreadsAuthor")
		)
		if comment.created_at then
			table.insert(lines, ui.text_line(comment.created_at, "UnifiedReviewThreadsContext"))
		end
		table.insert(lines, divider_line(24))
		local body = tostring(comment.body or "")
		if body == "" then
			table.insert(lines, "[empty]")
		else
			for line in (body .. "\n"):gmatch("([^\n]*)\n") do
				table.insert(lines, line)
			end
		end
	end
	return lines
end

function M.render_thread_lines(thread)
	return renderer.lines(M.render_thread_document(thread))
end

local function current_row_entry(session)
	local ui_state = session and session.ui or {}
	local win = ui_state.thread_panel_win
	if not win or not vim.api.nvim_win_is_valid(win) then
		return nil
	end
	local row = vim.api.nvim_win_get_cursor(win)[1]
	return (ui_state.thread_panel_rows or {})[row]
end

local function selected_row_entry(session)
	for _, entry in pairs((session and session.ui and session.ui.thread_panel_rows) or {}) do
		if entry.selected then
			return entry
		end
	end
	return nil
end

local function row_thread(session)
	local entry = selected_row_entry(session) or current_row_entry(session)
	if entry and entry.kind == "thread" then
		return entry.thread
	end
	local item = selected_list_item(session, threads.filtered_threads(session))
	return item and item.kind == "thread" and item.thread or nil
end

local function selected_row_line(session)
	for row, entry in pairs((session and session.ui and session.ui.thread_panel_rows) or {}) do
		if entry.selected then
			return row
		end
	end
	return nil
end

local function focus_selected_row(session)
	local win = session and session.ui and session.ui.thread_panel_win
	local row = selected_row_line(session)
	if not win or not row or not vim.api.nvim_win_is_valid(win) then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	local line_count = math.max(vim.api.nvim_buf_line_count(buf), 1)
	pcall(vim.api.nvim_win_set_cursor, win, { math.min(row, line_count), 0 })
end

local function move_thread_selection(session, delta)
	if not session or session._thread_composer then
		return
	end
	local visible = threads.filtered_threads(session)
	local entries = thread_tree_entries(session, visible)
	if #entries == 0 then
		return
	end
	local selected_key = session._thread_selected_key
	if not selected_key and session._thread_selected_id then
		selected_key = "thread:" .. session._thread_selected_id
	end
	local current_index
	for index, entry in ipairs(entries) do
		if entry.key == selected_key then
			current_index = index
			break
		end
	end
	local next_index
	if current_index then
		next_index = clamp(current_index + delta, 1, #entries)
	else
		next_index = delta < 0 and #entries or 1
	end
	set_selected_item(session, entries[next_index].node)
	M.render(session)
end

local function select_file_for_thread(session, thread)
	local path = thread and thread.target and thread.target.path
	if not path then
		return false
	end
	for index, file in ipairs(session.files or {}) do
		if file.path == path or file.old_path == path then
			selection.select_file(session, index)
			return true
		end
	end
	return false
end

local function focus_thread_target(session, thread)
	if not thread or not thread.target or not session.ui then
		return
	end
	local side = thread.target.side or thread.target.start_side or "right"
	local row = selection.row_for_target(session, thread.target, side) or 1
	local win = side == "left" and session.ui.left_window or session.ui.right_window
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
		local buf = vim.api.nvim_win_get_buf(win)
		local line_count = math.max(vim.api.nvim_buf_line_count(buf), 1)
		pcall(vim.api.nvim_win_set_cursor, win, { math.min(row, line_count), 0 })
	end
end

local function jump_to_thread(session, thread)
	if not thread then
		return
	end
	local changed_file = select_file_for_thread(session, thread)
	if changed_file then
		pcall(require("unified_review.ui.diff_view").render, session)
	end
	focus_thread_target(session, thread)
	vim.defer_fn(function()
		if state.get_active() == session then
			focus_thread_target(session, thread)
		end
	end, 120)
end

local function overview_size()
	local max_width = math.max(1, vim.o.columns - 4)
	local max_height = math.max(1, vim.o.lines - 4)
	local width = clamp(math.floor(vim.o.columns * 0.78), math.min(64, max_width), max_width)
	local height = clamp(math.floor(vim.o.lines * 0.78), math.min(18, max_height), max_height)
	return width, height
end

local function delete_thread_draft(thread)
	if not thread then
		return
	end
	local comment
	for _, candidate in ipairs(thread.comments or {}) do
		if candidate.state == "draft" then
			comment = candidate
			break
		end
	end
	comment = comment or (thread.comments or {})[1]
	if comment and comment.id then
		require("unified_review.session.manager").delete_draft(comment.id)
	end
end

local function strip_composer_padding(line)
	line = tostring(line or "")
	if line:sub(1, #HORIZONTAL_PADDING) == HORIZONTAL_PADDING then
		return line:sub(#HORIZONTAL_PADDING + 1)
	end
	return line
end

local function normalize_body_lines(lines, opts)
	opts = opts or {}
	local normalized = {}
	for _, line in ipairs(lines or {}) do
		table.insert(normalized, strip_composer_padding(line))
	end
	if opts.trim then
		while #normalized > 0 and normalized[1] == "" do
			table.remove(normalized, 1)
		end
		while #normalized > 0 and normalized[#normalized] == "" do
			table.remove(normalized, #normalized)
		end
	end
	return normalized
end

local function composer_region(session)
	local ui_state = session and session.ui or {}
	local info = ui_state.thread_panel_composer
	local buf = ui_state.thread_panel_buf
	if not info or not buf or not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end
	local start_pos = vim.api.nvim_buf_get_extmark_by_id(buf, M.compose_ns, info.start_mark, {})
	local footer_pos = vim.api.nvim_buf_get_extmark_by_id(buf, M.compose_ns, info.footer_mark, {})
	if not start_pos or not start_pos[1] or not footer_pos or not footer_pos[1] then
		return nil
	end
	local line = (vim.api.nvim_buf_get_lines(buf, start_pos[1], start_pos[1] + 1, false) or {})[1] or ""
	local start_col = line:sub(1, #HORIZONTAL_PADDING) == HORIZONTAL_PADDING and #HORIZONTAL_PADDING or 0
	return {
		buf = buf,
		start_row = start_pos[1],
		start_col = start_col,
		footer_row = footer_pos[1],
	}
end

local function read_composer_lines(session, opts)
	local region = composer_region(session)
	if not region then
		return nil
	end
	local lines = vim.api.nvim_buf_get_lines(region.buf, region.start_row, region.footer_row, false)
	return normalize_body_lines(lines, opts)
end

local function capture_composer(session)
	if not session or not session._thread_composer then
		return
	end
	local lines = read_composer_lines(session, { trim = false })
	if lines then
		session._thread_composer.lines = #lines > 0 and lines or { "" }
	end
end

local function focus_composer(session)
	local region = composer_region(session)
	local win = session and session.ui and session.ui.thread_panel_win
	if not region or not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	vim.api.nvim_set_current_win(win)
	pcall(vim.api.nvim_win_set_cursor, win, { region.start_row + 1, region.start_col })
	vim.cmd("startinsert")
end

local function begin_reply(session, thread)
	if not session or not thread or not thread.id then
		return
	end
	capture_composer(session)
	session._thread_selected_id = thread.id
	session._thread_composer = { thread_id = thread.id, lines = { "" } }
	M.render(session)
	vim.schedule(function()
		if state.get_active() == session then
			focus_composer(session)
		end
	end)
end

local function cancel_reply(session)
	if not session or not session._thread_composer then
		return false
	end
	session._thread_composer = nil
	pcall(vim.cmd, "stopinsert")
	M.render(session)
	return true
end

local function save_reply(session)
	if not session or not session._thread_composer then
		return false
	end
	local composer = session._thread_composer
	local body = table.concat(read_composer_lines(session, { trim = true }) or {}, "\n")
	if vim.trim(body) == "" then
		vim.notify("Reply body is required", vim.log.levels.ERROR, { title = "unified-review" })
		focus_composer(session)
		return true
	end
	session._thread_composer = nil
	pcall(vim.cmd, "stopinsert")
	local result, err = require("unified_review.session.manager").reply(composer.thread_id, body)
	if not result then
		session._thread_composer = composer
		M.render(session)
		vim.notify(err and err.message or "failed to save reply", vim.log.levels.ERROR, { title = "unified-review" })
		focus_composer(session)
		return true
	end
	M.render(session)
	return true
end

--- Render the overview buffer content.
function M.render(session)
	if not session or not session.ui or not session.ui.thread_panel_buf then
		return
	end
	local buf = session.ui.thread_panel_buf
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	ensure_highlights()
	capture_composer(session)
	local lines, row_map, _, meta = build_lines(session)
	local document = style_lines(lines)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_clear_namespace(buf, M.compose_ns, 0, -1)
	local rendered = renderer.render(buf, M.ns, document)
	session.ui.thread_panel_composer = nil
	if meta and meta.composer then
		local start_row = meta.composer.start_row - 1
		local footer_row = meta.composer.footer_row - 1
		session.ui.thread_panel_composer = {
			start_mark = vim.api.nvim_buf_set_extmark(buf, M.compose_ns, start_row, 0, {
				right_gravity = false,
			}),
			footer_mark = vim.api.nvim_buf_set_extmark(buf, M.compose_ns, footer_row, 0, {
				right_gravity = true,
			}),
		}
	end
	vim.bo[buf].modifiable = session.ui.thread_panel_composer ~= nil
	vim.bo[buf].modified = false
	session.ui.thread_panel_rows = row_map
	if not session._thread_composer and rendered then
		focus_selected_row(session)
	end
end

local function set_keymaps(session, buf)
	local function map(lhs, rhs)
		vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true })
	end
	local toggle_fold
	map("q", function()
		M.close(session)
	end)
	map("j", function()
		move_thread_selection(session, 1)
	end)
	map("k", function()
		move_thread_selection(session, -1)
	end)
	map("<Down>", function()
		move_thread_selection(session, 1)
	end)
	map("<Up>", function()
		move_thread_selection(session, -1)
	end)
	map("<C-d>", function()
		move_thread_selection(session, 8)
	end)
	map("<PageDown>", function()
		move_thread_selection(session, 8)
	end)
	map("<C-u>", function()
		move_thread_selection(session, -8)
	end)
	map("<PageUp>", function()
		move_thread_selection(session, -8)
	end)
	map("<CR>", function()
		local entry = selected_row_entry(session) or current_row_entry(session)
		if entry and entry.kind == "file" then
			toggle_fold()
			return
		end
		jump_to_thread(session, row_thread(session))
	end)
	map("p", function()
		M.render(session)
	end)
	map("R", function()
		begin_reply(session, row_thread(session))
	end)
	map("e", function()
		local thread = row_thread(session)
		if thread then
			require("unified_review.session.manager").toggle_thread_export(thread.id)
			M.render(session)
		end
	end)
	map("r", function()
		local thread = row_thread(session)
		if thread then
			if thread.state == "resolved" then
				require("unified_review.session.manager").reopen_thread(thread.id)
			else
				require("unified_review.session.manager").resolve_thread(thread.id)
			end
			M.render(session)
		end
	end)
	map("P", function()
		require("unified_review.session.manager").publish_drafts()
		M.render(session)
	end)
	map("D", function()
		local thread = row_thread(session)
		if thread then
			delete_thread_draft(thread)
			M.render(session)
		end
	end)
	local function toggle_filter(key)
		local filter = filter_for(session)
		if key == "a" then
			local enable = not (filter.open and filter.resolved and filter.draft and filter.stale)
			filter.open = enable
			filter.resolved = enable
			filter.draft = enable
			filter.stale = enable
		else
			local map_key = { o = "open", v = "resolved", d = "draft", s = "stale" }
			local name = map_key[key]
			if name then
				filter[name] = not filter[name]
			end
		end
		session._thread_selected_id = nil
		session._thread_selected_key = nil
		M.render(session)
	end
	for _, key in ipairs({ "o", "v", "d", "s", "a" }) do
		map(key, function()
			toggle_filter(key)
		end)
	end
	map("c", function()
		session._thread_query = nil
		session._thread_filter = { open = true, resolved = true, draft = true, stale = true }
		session._thread_selected_id = nil
		session._thread_selected_key = nil
		M.render(session)
	end)
	local function prompt_filter()
		vim.ui.input({ prompt = "Filter review threads: ", default = session._thread_query or "" }, function(value)
			if value == nil then
				return
			end
			value = vim.trim(value)
			session._thread_query = value ~= "" and value or nil
			session._thread_selected_id = nil
			session._thread_selected_key = nil
			M.render(session)
		end)
	end
	map("F", prompt_filter)
	map("/", prompt_filter)
	map("S", function()
		session._thread_scope = threads.scope_for(session) == "project" and "current" or "project"
		session._thread_selected_id = nil
		session._thread_selected_key = nil
		M.render(session)
	end)
	toggle_fold = function()
		local entry = selected_row_entry(session) or current_row_entry(session)
		local path = entry and entry.path
		if not path then
			local thread = row_thread(session)
			path = thread and thread.target and thread.target.path
		end
		if path then
			local collapsed = collapsed_files_for(session)
			collapsed[path] = not collapsed[path]
			set_selected_item(session, { kind = "file", path = path })
			M.render(session)
		end
	end
	map("za", toggle_fold)
	map("<Space>", toggle_fold)
	vim.keymap.set({ "n", "i", "x" }, "<C-s>", function()
		save_reply(session)
	end, { buffer = buf, silent = true })
	vim.keymap.set({ "n", "i" }, "<Esc>", function()
		cancel_reply(session)
		return "<Esc>"
	end, { buffer = buf, expr = true, silent = true })
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			if save_reply(session) then
				return
			end
			vim.bo[buf].modified = false
		end,
	})
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		buffer = buf,
		callback = function()
			if session._thread_composer then
				return
			end
			vim.schedule(function()
				focus_selected_row(session)
			end)
		end,
	})
end

--- Open the project-wide review overview in a floating modal.
function M.open(session)
	if not session then
		session = state.get_active()
	end
	if not session then
		vim.notify("No active review session", vim.log.levels.INFO, { title = "unified-review" })
		return false
	end
	session.ui = session.ui or {}
	if session.ui.thread_panel_win and vim.api.nvim_win_is_valid(session.ui.thread_panel_win) then
		vim.api.nvim_set_current_win(session.ui.thread_panel_win)
		M.render(session)
		return true
	end

	local width, height = overview_size()
	local panel_win
	local popup = float.open({
		name = "unified-review://threads",
		lines = {},
		modifiable = false,
		filetype = "unified-review",
		width = width,
		height = height,
		min_width = width,
		max_width = width,
		min_height = height,
		max_height = height,
		title = " ◉ Review Overview ",
		zindex_key = "threads",
		default_keymaps = false,
		highlight_links = HIGHLIGHT_LINKS,
		win_options = {
			wrap = false,
			cursorline = true,
			winhighlight = float.winhighlight({
				FloatBorder = "UnifiedReviewThreadsBorder",
				FloatTitle = "UnifiedReviewThreadsTitle",
				FloatFooter = "UnifiedReviewThreadsFooter",
			}),
		},
		on_close = function()
			if session.ui and session.ui.thread_panel_win == panel_win then
				session._thread_composer = nil
				session.ui.thread_panel_buf = nil
				session.ui.thread_panel_win = nil
				session.ui.thread_panel_close = nil
				session.ui.thread_panel_rows = nil
				session.ui.thread_panel_composer = nil
			end
		end,
	})
	local buf = popup.buffer
	panel_win = popup.window
	session.ui.thread_panel_buf = buf
	session.ui.thread_panel_win = panel_win
	session.ui.thread_panel_close = popup.close
	set_keymaps(session, buf)
	M.render(session)
	return true
end

--- Close the review overview modal.
function M.close(session)
	if not session then
		session = state.get_active()
	end
	if not session or not session.ui or not session.ui.thread_panel_buf then
		return false
	end
	local close_fn = session.ui.thread_panel_close
	local win = session.ui.thread_panel_win
	local buf = session.ui.thread_panel_buf
	if close_fn then
		pcall(close_fn)
	else
		if win and vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
		if buf and vim.api.nvim_buf_is_valid(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
	session._thread_composer = nil
	session.ui.thread_panel_buf = nil
	session.ui.thread_panel_win = nil
	session.ui.thread_panel_close = nil
	session.ui.thread_panel_rows = nil
	session.ui.thread_panel_composer = nil
	session.ui.thread_panel_filter_buf = nil
	session.ui.thread_panel_filter_win = nil
	session.ui.thread_panel_prompt_buf = nil
	session.ui.thread_panel_prompt_win = nil
	return true
end

--- Toggle the review overview modal.
function M.toggle(session)
	if not session then
		session = state.get_active()
	end
	if
		session
		and session.ui
		and session.ui.thread_panel_win
		and vim.api.nvim_win_is_valid(session.ui.thread_panel_win)
	then
		return M.close(session)
	end
	return M.open(session)
end

--- Check if the review overview is open.
function M.is_open(session)
	if not session then
		session = state.get_active()
	end
	return session
			and session.ui
			and session.ui.thread_panel_win
			and vim.api.nvim_win_is_valid(session.ui.thread_panel_win)
		or false
end

return M
