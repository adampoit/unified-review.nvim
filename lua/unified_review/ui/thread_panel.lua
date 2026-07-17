--- Project-wide review overview buffer.
local float = require("unified_review.ui.float")
local ui = require("components")
local renderer = require("components.renderer")
local selection = require("unified_review.session.selection")
local state = require("unified_review.session.state")
local threads = require("unified_review.ui.thread_query")
local tree = require("components.tree")
local debug = require("unified_review.util.debug")

local M = {}

M.ns = vim.api.nvim_create_namespace("unified_review_thread_panel")
M.compose_ns = vim.api.nvim_create_namespace("unified_review_thread_panel_composer")
M.action_ns = vim.api.nvim_create_namespace("unified_review_thread_panel_actions")

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
local DISPLAY_STATES = { "open", "draft", "resolved", "stale" }

local function clamp(value, min_value, max_value)
	return math.max(min_value, math.min(max_value, value))
end

local function ensure_highlights()
	float.ensure_highlights(HIGHLIGHT_LINKS)
end

local HORIZONTAL_PADDING = "  "
local WIDE_LAYOUT_MIN_WIDTH = 96

local HELP_SECTIONS = {
	{
		title = "Navigate",
		items = {
			{ label = "j/k", text = "select thread" },
			{ label = "C-e/C-y", text = "scroll workspace" },
			{ label = "Enter", text = "open details or jump to code" },
			{ label = "Space/za", text = "collapse file" },
			{ label = "S", text = "toggle project/current-file scope" },
		},
	},
	{
		title = "Filter",
		items = {
			{ label = "/", text = "search threads" },
			{ label = "o/v/d/s", text = "toggle open/resolved/draft/stale" },
			{ label = "a", text = "toggle every state" },
			{ label = "c", text = "clear filters" },
		},
	},
	{
		title = "Act on selected thread",
		items = {
			{ label = "R", text = "reply" },
			{ label = "r", text = "resolve or reopen" },
			{ label = "e", text = "toggle export" },
			{ label = "P", text = "publish local drafts" },
			{ label = "D", text = "delete draft" },
		},
	},
	{
		title = "Panel",
		items = {
			{ label = "?", text = "toggle this help" },
			{ label = "Esc", text = "return to threads" },
			{ label = "q", text = "close" },
		},
	},
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

local function key_hint_lines(items, width)
	if not width or width <= 0 then
		return { key_hint_line(items) }
	end
	local lines = {}
	local current = {}
	for _, item in ipairs(items or {}) do
		local candidate = vim.list_extend(vim.deepcopy(current), { item })
		local text = renderer.flatten_line(key_hint_line(candidate)).text
		if #current > 0 and vim.fn.strdisplaywidth(text) > width then
			table.insert(lines, key_hint_line(current))
			current = { item }
		else
			current = candidate
		end
	end
	if #current > 0 then
		table.insert(lines, key_hint_line(current))
	end
	return #lines > 0 and lines or { key_hint_line({}) }
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

local function states_label(session)
	local filter = filter_for(session)
	local enabled = {}
	for _, state_name in ipairs(FILTER_STATES) do
		if filter[state_name] then
			table.insert(enabled, state_name)
		end
	end
	if #enabled == #FILTER_STATES then
		return "all states"
	end
	return #enabled > 0 and table.concat(enabled, ", ") or "no states"
end

local function summary_line(session)
	local summary = threads.summary(session)
	local parts = {}
	for _, state_name in ipairs(DISPLAY_STATES) do
		local count = summary[state_name] or 0
		if count > 0 then
			local label = state_name == "draft" and (count == 1 and "draft" or "drafts") or state_name
			table.insert(parts, string.format("%d %s", count, label))
		end
	end
	table.insert(parts, plural(summary.threads or 0, "thread") .. " total")
	return table.concat(parts, " · ")
end

local function filter_summary_line(session)
	local visible = threads.filtered_threads(session)
	local scope = threads.scope_for(session)
	local query = session._thread_query and vim.trim(session._thread_query) or ""
	local parts = {
		scope == "current" and "Current file" or "Project",
		states_label(session),
		query ~= "" and ("query: " .. query) or "no query",
	}
	if #visible ~= #(session.threads or {}) then
		table.insert(parts, string.format("%d/%d visible", #visible, #(session.threads or {})))
	end
	return table.concat(parts, " · ")
end

local content_width_for

function M.render_filter_lines(session)
	return { summary_line(session), filter_summary_line(session) }
end

local function file_counts(group)
	local counts = { open = 0, resolved = 0, draft = 0, stale = 0 }
	for _, thread in ipairs(group.threads or {}) do
		local st = thread_state(thread)
		counts[st] = (counts[st] or 0) + 1
	end
	local parts = {}
	for _, st in ipairs(DISPLAY_STATES) do
		if counts[st] and counts[st] > 0 then
			local label = st == "draft" and (counts[st] == 1 and "draft" or "drafts") or st
			table.insert(parts, string.format("%d %s", counts[st], label))
		end
	end
	return #parts > 0 and table.concat(parts, " · ") or "no visible threads"
end

content_width_for = function(session)
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

local function wrap_long_word(word, width)
	local lines = {}
	local current = ""
	for index = 0, vim.fn.strchars(word) - 1 do
		local char = vim.fn.strcharpart(word, index, 1)
		if current ~= "" and vim.fn.strdisplaywidth(current .. char) > width then
			table.insert(lines, current)
			current = char
		else
			current = current .. char
		end
	end
	if current ~= "" then
		table.insert(lines, current)
	end
	return lines
end

local function wrap_text(value, width)
	value = tostring(value or "")
	width = math.max(1, width)
	if value == "" then
		return { "" }
	end
	local lines = {}
	local current = ""
	for word in value:gmatch("%S+") do
		if vim.fn.strdisplaywidth(word) > width then
			if current ~= "" then
				table.insert(lines, current)
				current = ""
			end
			vim.list_extend(lines, wrap_long_word(word, width))
		else
			local candidate = current == "" and word or (current .. " " .. word)
			if vim.fn.strdisplaywidth(candidate) <= width then
				current = candidate
			else
				table.insert(lines, current)
				current = word
			end
		end
	end
	if current ~= "" then
		table.insert(lines, current)
	end
	return #lines > 0 and lines or { "" }
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
	local body_width = math.max(12, (content_width or 78) - 32)
	local height = session._thread_panel_pane_height and math.max(1, session._thread_panel_pane_height) or nil
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
					ui.text(plural(item.thread_count, "thread") .. " · " .. item.counts, "UnifiedReviewThreadsMuted"),
				}, { hl = "UnifiedReviewThreadsFile" })
			end
			local thread = item.thread or {}
			local th_target = thread.target or {}
			local st = thread_state(thread)
			local state_hl = state_highlight_name(st)
			local icon = STATE_ICONS[st] or "●"
			local state_label = thread_state_label(thread)
			local first = thread.comments and thread.comments[1]
			local author = first and (first.author or "local") or "local"
			local comment_count = #(thread.comments or {})
			local reply_count = math.max(0, comment_count - 1)
			local suffix = reply_count > 0
					and string.format(" · %d %s", reply_count, reply_count == 1 and "reply" or "replies")
				or ""
			local export_label = threads.export_icon(thread) ~= " " and " ⇪" or ""
			local body = truncate(preview_text(first), body_width)
			return ui.line({
				ui.text(icon .. " " .. state_label, state_hl),
				ui.text(export_label, "UnifiedReviewThreadsBadge"),
				ui.text(string.format("  %s · %s  %s%s", target_label(th_target), author, body, suffix)),
			})
		end,
	})
	return list.document, list.rows
end

local function append_detail_composer(lines, session, thread, meta, width)
	local composer = session._thread_composer
	if not composer then
		return
	end
	if not thread or thread.id ~= composer.thread_id then
		session._thread_composer = nil
		return
	end
	composer.body_height = math.max(4, math.min(8, composer.body_height or #(composer.lines or {})))
	table.insert(lines, "")
	table.insert(lines, section_line("Reply"))
	table.insert(lines, divider_line(math.max(12, width or 40)))
	meta.composer = { start_row = #lines + 1 }
	for _ = 1, composer.body_height do
		table.insert(lines, " ")
	end
	meta.composer.footer_row = #lines + 1
	table.insert(lines, divider_line(math.max(12, width or 40)))
end

local function detail_document(item, width, session, meta)
	meta = meta or {}
	if item and item.kind == "file" then
		return {
			label_value_line("File:", item.path),
			label_value_line("Threads:", plural(item.thread_count, "thread") .. " · " .. item.counts),
			label_value_line("State:", item.collapsed and "collapsed" or "expanded"),
			"",
			context_line("Press Enter or Space to collapse or expand this file."),
		}
	end

	local thread = item and item.thread or item
	if not thread then
		return { warning_line("No thread selected") }
	end
	local lines = M.render_thread_document(thread, width)
	append_detail_composer(lines, session, thread, meta, width)
	return lines
end

local function help_document(content_width)
	local lines = {
		section_line("Keyboard shortcuts"),
		context_line("Actions stay available without keeping every key on screen."),
	}
	for _, section in ipairs(HELP_SECTIONS) do
		table.insert(lines, "")
		table.insert(lines, section_line(section.title))
		for _, line in ipairs(key_hint_lines(section.items, content_width)) do
			table.insert(lines, line)
		end
	end
	return lines
end

local function append_thread_workspace(lines, row_map, session, visible, selected, content_width, meta)
	local use_columns = content_width >= WIDE_LAYOUT_MIN_WIDTH
	local view = session._thread_panel_view or "list"
	if use_columns then
		view = "list"
	elseif view == "detail" and (not selected or selected.kind ~= "thread") then
		view = "list"
		session._thread_panel_view = "list"
	end

	local base = #lines
	if not use_columns and view == "detail" then
		table.insert(lines, section_line("Thread details"))
		local detail_meta = {}
		local detail_lines = detail_document(selected, content_width, session, detail_meta)
		vim.list_extend(lines, detail_lines)
		if detail_meta.composer then
			meta.composer = {
				start_row = base + 1 + detail_meta.composer.start_row,
				footer_row = base + 1 + detail_meta.composer.footer_row,
				start_col = vim.fn.strdisplaywidth(HORIZONTAL_PADDING),
				width = content_width,
			}
		end
		return
	end

	if not use_columns then
		table.insert(lines, section_line("Threads"))
		local list_lines, local_row_map = build_thread_list(session, visible, selected, content_width)
		for index, line in ipairs(list_lines) do
			table.insert(lines, line)
			if local_row_map[index] then
				row_map[#lines] = local_row_map[index]
			end
		end
		return
	end

	local list_width = list_preview_width(content_width)
	local separator = " │ "
	local detail_width = math.max(36, content_width - list_width - vim.fn.strdisplaywidth(separator))
	local list_lines, local_row_map = build_thread_list(session, visible, selected, list_width)
	local detail_meta = {}
	local detail_lines = detail_document(selected, detail_width, session, detail_meta)
	table.insert(
		lines,
		ui.columns({
			{ child = section_line("Threads"), width = list_width, truncate = false },
			{ child = section_line("Details"), width = detail_width, truncate = false },
		}, { separator = separator })
	)
	local count = math.max(#list_lines, #detail_lines)
	for index = 1, count do
		table.insert(
			lines,
			ui.columns({
				{ child = list_lines[index] or "", width = list_width, truncate = true },
				{ child = detail_lines[index] or "", width = detail_width, truncate = true },
			}, { separator = separator })
		)
		if local_row_map[index] then
			row_map[#lines] = local_row_map[index]
		end
	end
	if detail_meta.composer then
		meta.composer = {
			start_row = base + 1 + detail_meta.composer.start_row,
			footer_row = base + 1 + detail_meta.composer.footer_row,
			start_col = vim.fn.strdisplaywidth(HORIZONTAL_PADDING) + list_width + vim.fn.strdisplaywidth(separator),
			width = detail_width,
		}
	end
end

local function build_lines(session)
	local visible = threads.filtered_threads(session)
	local selected = selected_list_item(session, visible)
	local summary = threads.summary(session)
	local content_width = content_width_for(session)
	local lines = {
		section_line(summary_line(session)),
		context_line(filter_summary_line(session)),
	}
	if session.kind == "github_pr" and (summary.local_draft or 0) > 0 then
		table.insert(
			lines,
			warning_line(string.format("%s ready to publish · P publish", plural(summary.local_draft, "local draft")))
		)
	end
	table.insert(lines, "")
	table.insert(lines, divider_line(content_width))

	local row_map = {}
	local meta = {}
	if session._thread_panel_help then
		vim.list_extend(lines, help_document(content_width))
		return lines, row_map, visible, meta
	end
	if #visible == 0 then
		table.insert(lines, "")
		table.insert(lines, section_line("Threads"))
		if #(session.threads or {}) == 0 then
			table.insert(lines, "No review threads yet.")
			table.insert(lines, context_line("Leave a comment from the diff to start the review."))
		else
			table.insert(lines, "No threads match the current filters.")
			table.insert(lines, context_line("Press c to clear filters or / to change the search."))
		end
		return lines, row_map, visible, meta
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
	session._thread_panel_pane_height = math.max(6, total_height - #lines - 3)
	append_thread_workspace(lines, row_map, session, visible, selected, content_width, meta)
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

function M.render_thread_document(thread, width)
	if not thread then
		return { warning_line("No thread selected") }
	end
	local th_target = thread.target or {}
	local st = thread_state(thread)
	local state_hl = state_highlight_name(st)
	local comments = thread.comments or {}
	local location = (th_target.side or th_target.start_side) and ((th_target.side or th_target.start_side) .. " ")
		or ""
	local exported = threads.export_icon(thread) ~= " " and " · ⇪ marked for export" or ""
	local lines = {
		ui.line({
			ui.text((STATE_ICONS[st] or "●") .. " " .. thread_state_label(thread), state_hl),
			ui.text(string.format(" · %s%s · %s", location, target_label(th_target), plural(#comments, "comment"))),
			ui.text(exported, "UnifiedReviewThreadsBadge"),
		}),
	}
	if th_target.path then
		table.insert(lines, context_line(th_target.path))
	end
	if thread.is_outdated then
		table.insert(lines, warning_line("This thread points to outdated code."))
	end
	if #comments == 0 then
		table.insert(lines, "")
		table.insert(lines, "No comments in this thread.")
		return lines
	end
	local body_width = math.max(12, (width or 78) - 2)
	for _, comment in ipairs(comments) do
		table.insert(lines, "")
		local author_line = comment.author or "local"
		if comment.created_at then
			author_line = author_line .. " · " .. comment.created_at
		end
		table.insert(lines, ui.text_line(author_line, "UnifiedReviewThreadsAuthor"))
		local body = tostring(comment.body or "")
		if body == "" then
			table.insert(lines, context_line("  Empty comment"))
		else
			for raw_line in (body .. "\n"):gmatch("([^\n]*)\n") do
				if raw_line == "" then
					table.insert(lines, "")
				else
					for _, body_line in ipairs(wrap_text(raw_line, body_width - 2)) do
						table.insert(lines, "  " .. body_line)
					end
				end
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

local function normalize_path(path, root)
	if not path then
		return nil
	end
	path = tostring(path):gsub("\\", "/"):gsub("^%./", "")
	if path:match("^/") and root and root ~= "" then
		local real_root = vim.loop.fs_realpath(root) or vim.fn.fnamemodify(root, ":p")
		local real_path = vim.loop.fs_realpath(path) or vim.fn.fnamemodify(path, ":p")
		real_root = tostring(real_root):gsub("\\", "/"):gsub("/$", "")
		real_path = tostring(real_path):gsub("\\", "/")
		local prefix = real_root .. "/"
		if real_path:sub(1, #prefix) == prefix then
			return real_path:sub(#prefix + 1)
		end
	end
	return path
end

local function select_file_for_thread(session, thread)
	local path = thread and thread.target and thread.target.path
	if not path then
		return false
	end
	local root = session and session.target and (session.target.root or session.target.worktree_root)
	path = normalize_path(path, root)
	for index, file in ipairs(session.files or {}) do
		if normalize_path(file.path, root) == path or normalize_path(file.old_path, root) == path then
			selection.select_file(session, index)
			return true
		end
	end
	return false
end

local function buffer_snapshot(buf)
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return { id = buf, valid = false }
	end
	local has_comment_keymap = false
	for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
		if map.rhs == "<Cmd>UnifiedReview comment<CR>" or map.rhs == "<cmd>UnifiedReview comment<cr>" then
			has_comment_keymap = true
			break
		end
	end
	return {
		id = buf,
		valid = true,
		name = vim.api.nvim_buf_get_name(buf),
		line_count = vim.api.nvim_buf_line_count(buf),
		has_comment_keymap = has_comment_keymap,
	}
end

local function window_snapshot(win)
	if not (win and vim.api.nvim_win_is_valid(win)) then
		return { id = win, valid = false }
	end
	local cursor = vim.api.nvim_win_get_cursor(win)
	return {
		id = win,
		valid = true,
		buf = vim.api.nvim_win_get_buf(win),
		cursor = { cursor[1], cursor[2] },
	}
end

local function codediff_snapshot(session)
	local ui_state = session and session.ui or {}
	local snapshot = {
		codediff_tab = ui_state.codediff_tab,
		left_buffer = buffer_snapshot(ui_state.left_buffer),
		right_buffer = buffer_snapshot(ui_state.right_buffer),
		left_window = window_snapshot(ui_state.left_window),
		right_window = window_snapshot(ui_state.right_window),
		selection_file_index = session and session.selection and session.selection.file_index,
		current_file = (selection.current_file(session) or {}).path,
	}
	local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
	if ok and ui_state.codediff_tab then
		local left_buf, right_buf = lifecycle.get_buffers(ui_state.codediff_tab)
		local left_win, right_win = lifecycle.get_windows(ui_state.codediff_tab)
		local original_path, modified_path = lifecycle.get_paths(ui_state.codediff_tab)
		snapshot.lifecycle = {
			left_buffer = buffer_snapshot(left_buf),
			right_buffer = buffer_snapshot(right_buf),
			left_window = window_snapshot(left_win),
			right_window = window_snapshot(right_win),
			original_path = original_path,
			modified_path = modified_path,
		}
		local codediff_session = lifecycle.get_session(ui_state.codediff_tab)
		if codediff_session then
			snapshot.lifecycle.mode = codediff_session.mode
			snapshot.lifecycle.layout = codediff_session.layout
			snapshot.lifecycle.single_pane = codediff_session.single_pane
		end
	end
	return snapshot
end

local function sync_diff_ui(session)
	local ok, diff_view = pcall(require, "unified_review.ui.diff_view")
	if not ok then
		debug.event("thread.jump.sync_error", { error = diff_view })
		return
	end
	if type(diff_view.sync) == "function" then
		pcall(diff_view.sync, session)
	end
	if type(diff_view._attach_review_keymaps) == "function" then
		pcall(diff_view._attach_review_keymaps, session)
	end
end

local function target_row(thread)
	local target = thread and thread.target or {}
	return tonumber(target.line) or tonumber(target.start_line) or 1
end

local function focus_thread_target(session, thread, opts)
	if not thread or not thread.target or not session.ui then
		debug.event("thread.jump.focus.skip", { reason = "missing-thread-or-ui", thread = thread and thread.id })
		return false
	end
	opts = opts or {}
	if opts.sync then
		sync_diff_ui(session)
	end
	local selected = select_file_for_thread(session, thread)
	local side = thread.target.side or thread.target.start_side or "right"
	local row = selection.row_for_target(session, thread.target, side) or target_row(thread)
	local win = side == "left" and session.ui.left_window or session.ui.right_window
	local fallback = false
	if not (win and vim.api.nvim_win_is_valid(win)) then
		win = side == "left" and session.ui.right_window or session.ui.left_window
		fallback = true
	end
	if not (win and vim.api.nvim_win_is_valid(win)) then
		debug.event("thread.jump.focus.fail", {
			thread = thread.id,
			target = thread.target,
			side = side,
			row = row,
			selected = selected,
			snapshot = codediff_snapshot(session),
		})
		return false
	end
	vim.api.nvim_set_current_win(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local line_count = math.max(vim.api.nvim_buf_line_count(buf), 1)
	pcall(vim.api.nvim_win_set_cursor, win, { math.min(row, line_count), 0 })
	pcall(vim.api.nvim_win_call, win, function()
		vim.cmd("normal! zz")
	end)
	debug.event("thread.jump.focus", {
		thread = thread.id,
		target = thread.target,
		side = side,
		row = row,
		clamped_row = math.min(row, line_count),
		selected = selected,
		fallback_window = fallback,
		win = win,
		buf = buf,
		buf_name = vim.api.nvim_buf_get_name(buf),
		line_count = line_count,
		snapshot = codediff_snapshot(session),
	})
	return true
end

local function diff_shows_thread(session, thread)
	local root = session and session.target and (session.target.root or session.target.worktree_root)
	local expected = normalize_path(thread and thread.target and thread.target.path, root)
	local tab = session and session.ui and session.ui.codediff_tab
	if not expected or not tab then
		return true
	end
	local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
	if not ok then
		return true
	end
	local original_path, modified_path = lifecycle.get_paths(tab)
	return normalize_path(original_path, root) == expected or normalize_path(modified_path, root) == expected
end

local function render_thread_file_if_needed(session, thread)
	if diff_shows_thread(session, thread) then
		return false
	end
	debug.event("thread.jump.render_retry", { thread = thread.id, target = thread.target })
	pcall(require("unified_review.ui.diff_view").render, session, {
		auto_scroll_to_first_hunk = false,
	})
	return true
end

local function target_buffer_is_ready(session, thread)
	local side = thread and thread.target and (thread.target.side or thread.target.start_side) or "right"
	local win = side == "left" and session.ui.left_window or session.ui.right_window
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	return vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)) >= target_row(thread)
end

local function jump_to_thread(session, thread)
	if not thread then
		debug.event("thread.jump.skip", { reason = "nil-thread" })
		return
	end
	debug.event("thread.jump.start", {
		session = session and session.id,
		kind = session and session.kind,
		provider = session and session.provider,
		thread = thread.id,
		target = thread.target,
		snapshot = codediff_snapshot(session),
	})
	M.close(session)
	session._thread_jump_generation = (session._thread_jump_generation or 0) + 1
	local generation = session._thread_jump_generation
	local settled = false
	local changed_file = select_file_for_thread(session, thread)
	debug.event("thread.jump.select_file", {
		thread = thread.id,
		changed_file = changed_file,
		selection_file_index = session and session.selection and session.selection.file_index,
		current_file = (selection.current_file(session) or {}).path,
	})
	if changed_file then
		local ok, err = pcall(require("unified_review.ui.diff_view").render, session, {
			auto_scroll_to_first_hunk = false,
		})
		debug.event(
			"thread.jump.render",
			{ ok = ok, error = not ok and err or nil, snapshot = codediff_snapshot(session) }
		)
	end
	focus_thread_target(session, thread)
	settled = target_buffer_is_ready(session, thread) and diff_shows_thread(session, thread)
	for _, delay in ipairs({ 40, 120, 250, 600, 1000, 1200, 1500, 2000, 2500, 3000, 3500, 4000 }) do
		vim.defer_fn(function()
			local panel_open = session.ui
				and session.ui.thread_panel_win
				and vim.api.nvim_win_is_valid(session.ui.thread_panel_win)
			if state.get_active() == session and session._thread_jump_generation == generation and not panel_open then
				debug.event("thread.jump.retry", { thread = thread.id, delay = delay })
				local rendered = render_thread_file_if_needed(session, thread)
				if rendered then
					settled = false
					for _, recovery_delay in ipairs({ 100, 250, 500 }) do
						vim.defer_fn(function()
							local recovery_panel_open = session.ui
								and session.ui.thread_panel_win
								and vim.api.nvim_win_is_valid(session.ui.thread_panel_win)
							if
								state.get_active() == session
								and session._thread_jump_generation == generation
								and not recovery_panel_open
								and diff_shows_thread(session, thread)
								and target_buffer_is_ready(session, thread)
							then
								focus_thread_target(session, thread, { sync = true })
								settled = true
							end
						end, recovery_delay)
					end
				end
				if rendered or not settled or not target_buffer_is_ready(session, thread) then
					focus_thread_target(session, thread, { sync = true })
					settled = target_buffer_is_ready(session, thread) and diff_shows_thread(session, thread)
				end
			else
				debug.event(
					"thread.jump.retry.skip",
					{ thread = thread.id, delay = delay, reason = "inactive-session" }
				)
			end
		end, delay)
	end
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

local function normalize_body_lines(lines, opts)
	opts = opts or {}
	local normalized = vim.deepcopy(lines or {})
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

local function read_composer_lines(session, opts)
	local buf = session and session.ui and session.ui.thread_panel_composer_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end
	return normalize_body_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false), opts)
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

local function close_composer_window(session)
	local ui_state = session and session.ui or {}
	session._thread_composer_closing = true
	if ui_state.thread_panel_composer_group then
		pcall(vim.api.nvim_del_augroup_by_id, ui_state.thread_panel_composer_group)
	end
	if ui_state.thread_panel_composer_win and vim.api.nvim_win_is_valid(ui_state.thread_panel_composer_win) then
		pcall(vim.api.nvim_win_close, ui_state.thread_panel_composer_win, true)
	end
	if ui_state.thread_panel_composer_buf and vim.api.nvim_buf_is_valid(ui_state.thread_panel_composer_buf) then
		pcall(vim.api.nvim_buf_delete, ui_state.thread_panel_composer_buf, { force = true })
	end
	ui_state.thread_panel_composer_win = nil
	ui_state.thread_panel_composer_buf = nil
	ui_state.thread_panel_composer_group = nil
	session._thread_composer_closing = false
end

local function focus_composer(session)
	local win = session and session.ui and session.ui.thread_panel_composer_win
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	vim.api.nvim_set_current_win(win)
	vim.cmd("startinsert")
end

local open_composer_window

local function begin_reply(session, thread)
	if not session or not thread or not thread.id then
		return
	end
	capture_composer(session)
	session._thread_selected_id = thread.id
	if content_width_for(session) < WIDE_LAYOUT_MIN_WIDTH then
		session._thread_panel_view = "detail"
	end
	session._thread_composer = { thread_id = thread.id, lines = { "" }, body_height = 4 }
	M.render(session)
	vim.schedule(function()
		if state.get_active() == session then
			open_composer_window(session)
		end
	end)
end

local function cancel_reply(session)
	if not session or not session._thread_composer then
		return false
	end
	pcall(vim.cmd, "stopinsert")
	close_composer_window(session)
	session._thread_composer = nil
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
	local result, err = require("unified_review.session.manager").reply(composer.thread_id, body)
	if not result then
		vim.notify(err and err.message or "Failed to save reply", vim.log.levels.ERROR, { title = "unified-review" })
		focus_composer(session)
		return true
	end
	pcall(vim.cmd, "stopinsert")
	close_composer_window(session)
	session._thread_composer = nil
	M.render(session)
	return true
end

open_composer_window = function(session)
	local ui_state = session and session.ui or {}
	local geometry = ui_state.thread_panel_composer
	local panel_win = ui_state.thread_panel_win
	if not geometry or not panel_win or not vim.api.nvim_win_is_valid(panel_win) then
		return
	end
	if ui_state.thread_panel_composer_win and vim.api.nvim_win_is_valid(ui_state.thread_panel_composer_win) then
		focus_composer(session)
		return
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "markdown"
	pcall(vim.api.nvim_buf_set_name, buf, "unified-review://reply")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, session._thread_composer.lines or { "" })
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "win",
		win = panel_win,
		row = geometry.row,
		col = geometry.col,
		width = math.max(1, geometry.width),
		height = session._thread_composer.body_height or 4,
		style = "minimal",
		focusable = true,
		noautocmd = true,
		zindex = 80,
	})
	for name, value in pairs({
		wrap = true,
		linebreak = true,
		breakindent = true,
		number = false,
		relativenumber = false,
		signcolumn = "no",
		foldcolumn = "0",
		winhighlight = "NormalFloat:UnifiedReviewFloatNormal",
	}) do
		pcall(vim.api.nvim_set_option_value, name, value, { win = win, scope = "local" })
	end
	ui_state.thread_panel_composer_buf = buf
	ui_state.thread_panel_composer_win = win
	local group = vim.api.nvim_create_augroup("unified_review_thread_reply_" .. tostring(buf), { clear = true })
	ui_state.thread_panel_composer_group = group

	vim.keymap.set({ "n", "i", "x" }, "<C-s>", function()
		save_reply(session)
	end, { buffer = buf, silent = true })
	vim.keymap.set({ "n", "i" }, "<Esc>", function()
		cancel_reply(session)
	end, { buffer = buf, silent = true })
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = group,
		buffer = buf,
		callback = function()
			save_reply(session)
		end,
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = group,
		buffer = buf,
		callback = function()
			local height = clamp(vim.api.nvim_buf_line_count(buf), 4, 8)
			if session._thread_composer and height ~= session._thread_composer.body_height then
				capture_composer(session)
				session._thread_composer.body_height = height
				vim.schedule(function()
					if state.get_active() == session then
						M.render(session)
					end
				end)
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		pattern = tostring(win),
		callback = function()
			if session._thread_composer and not session._thread_composer_closing then
				vim.schedule(function()
					cancel_reply(session)
				end)
			end
		end,
	})
	vim.api.nvim_win_set_cursor(win, { math.max(1, vim.api.nvim_buf_line_count(buf)), 0 })
	vim.cmd("startinsert")
end

local function footer_items(session)
	if session._thread_composer then
		return {
			{ label = "C-s", text = "save reply" },
			{ label = "Esc", text = "cancel" },
		}
	end
	if session._thread_panel_help then
		return {
			{ label = "Esc", text = "back" },
			{ label = "q", text = "close" },
		}
	end

	local content_width = content_width_for(session)
	local narrow = content_width < WIDE_LAYOUT_MIN_WIDTH
	local compact = content_width < 72
	local item = selected_list_item(session, threads.filtered_threads(session))
	if narrow and session._thread_panel_view == "detail" then
		if compact then
			return {
				{ label = "Enter", text = "jump" },
				{ label = "R", text = "reply" },
				{ label = "Esc", text = "back" },
				{ label = "?", text = "help" },
				{ label = "q", text = "close" },
			}
		end
		return {
			{ label = "Enter", text = "jump" },
			{ label = "R", text = "reply" },
			{ label = "r", text = "resolve" },
			{ label = "Esc", text = "threads" },
			{ label = "?", text = "help" },
			{ label = "q", text = "close" },
		}
	end
	if not item then
		return {
			{ label = "/", text = "filter" },
			{ label = "?", text = "help" },
			{ label = "q", text = "close" },
		}
	end
	if item.kind == "file" then
		local items = {
			{ label = "Enter", text = item.collapsed and "expand" or "collapse" },
		}
		if not compact then
			vim.list_extend(items, {
				{ label = "/", text = "filter" },
				{ label = "S", text = "scope" },
			})
		end
		table.insert(items, { label = "?", text = "help" })
		table.insert(items, { label = "q", text = "close" })
		return items
	end
	local primary = narrow and "details" or "jump"
	local items = {
		{ label = "Enter", text = primary },
		{ label = "R", text = "reply" },
	}
	if not compact then
		table.insert(items, {
			label = "r",
			text = thread_state(item.thread) == "resolved" and "reopen" or "resolve",
		})
	end
	if not narrow then
		vim.list_extend(items, {
			{ label = "e", text = "export" },
			{ label = "/", text = "filter" },
		})
	end
	table.insert(items, { label = "?", text = "help" })
	table.insert(items, { label = "q", text = "close" })
	return items
end

local function close_action_bar(session)
	local ui_state = session and session.ui or {}
	if ui_state.thread_panel_action_win and vim.api.nvim_win_is_valid(ui_state.thread_panel_action_win) then
		pcall(vim.api.nvim_win_close, ui_state.thread_panel_action_win, true)
	end
	if ui_state.thread_panel_action_buf and vim.api.nvim_buf_is_valid(ui_state.thread_panel_action_buf) then
		pcall(vim.api.nvim_buf_delete, ui_state.thread_panel_action_buf, { force = true })
	end
	ui_state.thread_panel_action_win = nil
	ui_state.thread_panel_action_buf = nil
end

local function render_action_bar(session)
	local ui_state = session and session.ui or {}
	local panel_win = ui_state.thread_panel_win
	if not panel_win or not vim.api.nvim_win_is_valid(panel_win) then
		return
	end
	local width = vim.api.nvim_win_get_width(panel_win)
	local height = vim.api.nvim_win_get_height(panel_win)
	local buf = ui_state.thread_panel_action_buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		pcall(vim.api.nvim_buf_set_name, buf, "unified-review://thread-actions")
		ui_state.thread_panel_action_buf = buf
	end

	local action_line = key_hint_line(footer_items(session))
	local action_width = vim.fn.strdisplaywidth(renderer.flatten_line(action_line).text)
	local right_padding = "  "
	local padding = string.rep(" ", math.max(0, width - action_width - vim.fn.strdisplaywidth(right_padding)))
	vim.bo[buf].modifiable = true
	renderer.render(buf, M.action_ns, {
		divider_line(width),
		ui.line({ ui.text(padding), action_line, ui.text(right_padding) }, { truncate_width = width }),
	})
	vim.bo[buf].modifiable = false

	local action_win = ui_state.thread_panel_action_win
	local config = {
		relative = "win",
		win = panel_win,
		row = math.max(0, height - 2),
		col = 0,
		width = width,
		height = 2,
		style = "minimal",
		focusable = false,
		noautocmd = true,
		zindex = 70,
	}
	if action_win and vim.api.nvim_win_is_valid(action_win) then
		pcall(vim.api.nvim_win_set_config, action_win, config)
	else
		action_win = vim.api.nvim_open_win(buf, false, config)
		ui_state.thread_panel_action_win = action_win
	end
	pcall(vim.api.nvim_set_option_value, "winhighlight", "NormalFloat:UnifiedReviewFloatNormal", {
		win = action_win,
		scope = "local",
	})
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
		session.ui.thread_panel_composer = {
			row = meta.composer.start_row - 1,
			col = meta.composer.start_col or 0,
			width = meta.composer.width or content_width_for(session),
		}
		local composer_win = session.ui.thread_panel_composer_win
		if composer_win and vim.api.nvim_win_is_valid(composer_win) then
			pcall(vim.api.nvim_win_set_config, composer_win, {
				relative = "win",
				win = session.ui.thread_panel_win,
				row = session.ui.thread_panel_composer.row,
				col = session.ui.thread_panel_composer.col,
				width = math.max(1, session.ui.thread_panel_composer.width),
				height = session._thread_composer and session._thread_composer.body_height or 4,
			})
		end
	end
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false
	session.ui.thread_panel_rows = row_map
	render_action_bar(session)
	if not session._thread_composer and rendered then
		if next(row_map) then
			focus_selected_row(session)
		elseif session.ui.thread_panel_win and vim.api.nvim_win_is_valid(session.ui.thread_panel_win) then
			pcall(vim.api.nvim_win_set_cursor, session.ui.thread_panel_win, { 1, 0 })
		end
	end
end

local function set_keymaps(session, buf)
	local function map(lhs, rhs)
		vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true })
	end
	local toggle_fold
	local function detail_is_focused()
		return session._thread_panel_help
			or (content_width_for(session) < WIDE_LAYOUT_MIN_WIDTH and session._thread_panel_view == "detail")
	end
	local function navigate(delta, normal_command)
		if detail_is_focused() then
			pcall(vim.cmd, "normal! " .. normal_command)
		else
			move_thread_selection(session, delta)
		end
	end
	map("q", function()
		M.close(session)
	end)
	map("j", function()
		navigate(1, "j")
	end)
	map("k", function()
		navigate(-1, "k")
	end)
	map("<Down>", function()
		navigate(1, "j")
	end)
	map("<Up>", function()
		navigate(-1, "k")
	end)
	map("<C-d>", function()
		navigate(8, "8j")
	end)
	map("<PageDown>", function()
		navigate(8, "8j")
	end)
	map("<C-u>", function()
		navigate(-8, "8k")
	end)
	map("<PageUp>", function()
		navigate(-8, "8k")
	end)
	map("<CR>", function()
		if session._thread_panel_help then
			return
		end
		local entry = selected_row_entry(session) or current_row_entry(session)
		debug.event("thread.panel.enter", {
			entry = entry and {
				kind = entry.kind,
				path = entry.path,
				key = entry.key,
				selected = entry.selected,
				thread = entry.thread and entry.thread.id,
			},
			selected_id = session._thread_selected_id,
			selected_key = session._thread_selected_key,
			current_row = session.ui and session.ui.thread_panel_win and vim.api.nvim_win_is_valid(
				session.ui.thread_panel_win
			) and vim.api.nvim_win_get_cursor(session.ui.thread_panel_win)[1] or nil,
		})
		if content_width_for(session) < WIDE_LAYOUT_MIN_WIDTH and session._thread_panel_view == "detail" then
			jump_to_thread(session, row_thread(session))
			return
		end
		if entry and entry.kind == "file" then
			toggle_fold()
			return
		end
		if content_width_for(session) < WIDE_LAYOUT_MIN_WIDTH then
			session._thread_panel_view = "detail"
			M.render(session)
			return
		end
		jump_to_thread(session, row_thread(session))
	end)
	map("p", function()
		M.render(session)
	end)
	map("R", function()
		if not session._thread_panel_help then
			begin_reply(session, row_thread(session))
		end
	end)
	map("?", function()
		if session._thread_composer then
			return
		end
		session._thread_panel_help = not session._thread_panel_help
		M.render(session)
	end)
	map("e", function()
		if session._thread_panel_help then
			return
		end
		local thread = row_thread(session)
		if thread then
			require("unified_review.session.manager").toggle_thread_export(thread.id)
			M.render(session)
		end
	end)
	map("r", function()
		if session._thread_panel_help then
			return
		end
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
		if session._thread_panel_help then
			return
		end
		require("unified_review.session.manager").publish_drafts()
		M.render(session)
	end)
	map("D", function()
		if session._thread_panel_help then
			return
		end
		local thread = row_thread(session)
		if thread then
			delete_thread_draft(thread)
			M.render(session)
		end
	end)
	local function toggle_filter(key)
		if session._thread_panel_help then
			return
		end
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
		session._thread_panel_view = "list"
		M.render(session)
	end
	for _, key in ipairs({ "o", "v", "d", "s", "a" }) do
		map(key, function()
			toggle_filter(key)
		end)
	end
	map("c", function()
		if session._thread_panel_help then
			return
		end
		session._thread_query = nil
		session._thread_filter = { open = true, resolved = true, draft = true, stale = true }
		session._thread_selected_id = nil
		session._thread_selected_key = nil
		session._thread_panel_view = "list"
		M.render(session)
	end)
	local function prompt_filter()
		if session._thread_panel_help then
			return
		end
		vim.ui.input({ prompt = "Filter review threads: ", default = session._thread_query or "" }, function(value)
			if value == nil then
				return
			end
			value = vim.trim(value)
			session._thread_query = value ~= "" and value or nil
			session._thread_selected_id = nil
			session._thread_selected_key = nil
			session._thread_panel_view = "list"
			M.render(session)
		end)
	end
	map("F", prompt_filter)
	map("/", prompt_filter)
	map("S", function()
		if session._thread_panel_help then
			return
		end
		session._thread_scope = threads.scope_for(session) == "project" and "current" or "project"
		session._thread_selected_id = nil
		session._thread_selected_key = nil
		session._thread_panel_view = "list"
		M.render(session)
	end)
	toggle_fold = function()
		if session._thread_panel_help then
			return
		end
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
			session._thread_panel_view = "list"
			M.render(session)
		end
	end
	map("za", toggle_fold)
	map("<Space>", toggle_fold)
	vim.keymap.set({ "n", "i", "x" }, "<C-s>", function()
		save_reply(session)
	end, { buffer = buf, silent = true })
	vim.keymap.set({ "n", "i" }, "<Esc>", function()
		if cancel_reply(session) then
			return
		end
		pcall(vim.cmd, "stopinsert")
		if session._thread_panel_help then
			session._thread_panel_help = false
			M.render(session)
		elseif content_width_for(session) < WIDE_LAYOUT_MIN_WIDTH and session._thread_panel_view == "detail" then
			session._thread_panel_view = "list"
			M.render(session)
		end
	end, { buffer = buf, silent = true })
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
	session._thread_jump_generation = (session._thread_jump_generation or 0) + 1
	session._thread_panel_view = session._thread_panel_view or "list"
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
			close_composer_window(session)
			close_action_bar(session)
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
	if session._thread_panel_saved_view then
		pcall(vim.api.nvim_win_call, panel_win, function()
			vim.fn.winrestview(session._thread_panel_saved_view)
		end)
	end
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
	close_composer_window(session)
	close_action_bar(session)
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_call, win, function()
			session._thread_panel_saved_view = vim.fn.winsaveview()
		end)
	end
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
	session._thread_panel_help = false
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
