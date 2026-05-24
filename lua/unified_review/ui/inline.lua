--- Inline thread rendering using virtual lines near target lines.
---
--- Virtual lines add screen rows to the diff without mutating the buffer, so
--- Neovim's file line numbers stay aligned with the reviewed file.
local comment_status = require("unified_review.domain.comment_status")
local review_thread = require("unified_review.domain.review_thread")

local M = {}

local inline_ns = vim.api.nvim_create_namespace("unified_review_inline_virt")
local FILLER_TEXT = string.rep("╱", 500)
local FILLER_HL = "CodeDiffFiller"

local HIGHLIGHTS = {
	UnifiedReviewInlineBorder = "Comment",
	UnifiedReviewInlineHeader = "Title",
	UnifiedReviewInlineAuthor = "Identifier",
	UnifiedReviewInlineBody = "Comment",
	UnifiedReviewInlineMeta = "NonText",
	UnifiedReviewInlineOpen = "DiagnosticInfo",
	UnifiedReviewInlineResolved = "DiagnosticOk",
	UnifiedReviewInlineDraft = "String",
	UnifiedReviewInlineStale = "WarningMsg",
}

local STATE_ICONS = {
	open = "●",
	action_required = "!",
	waiting_review = "○",
	resolved = "✓",
	stale = "⚠",
}

local function ensure_highlights()
	for name, link in pairs(HIGHLIGHTS) do
		pcall(vim.api.nvim_set_hl, 0, name, { default = true, link = link })
	end
end

local function display_width(value)
	return vim.fn.strdisplaywidth(value or "")
end

local function strchars(value)
	return vim.fn.strchars(value or "")
end

local function fill_text(fill, width)
	fill = fill or " "
	if width <= 0 or fill == "" then
		return ""
	end
	local text = ""
	while display_width(text) < width do
		text = text .. fill
	end
	if display_width(text) == width then
		return text
	end
	local out = ""
	for i = 0, strchars(text) - 1 do
		local ch = vim.fn.strcharpart(text, i, 1)
		if display_width(out .. ch) > width then
			break
		end
		out = out .. ch
	end
	return out
end

local function pad_right(value, width)
	value = value or ""
	return value .. fill_text(" ", width - display_width(value))
end

local function truncate(value, width)
	value = tostring(value or "")
	if width <= 0 then
		return ""
	end
	if display_width(value) <= width then
		return value
	end
	if width <= 1 then
		return "…"
	end
	local out = ""
	for i = 0, strchars(value) - 1 do
		local ch = vim.fn.strcharpart(value, i, 1)
		if display_width(out .. ch .. "…") > width then
			break
		end
		out = out .. ch
	end
	return out .. "…"
end

local function wrap_long_word(word, width)
	local lines = {}
	local current = ""
	for i = 0, strchars(word) - 1 do
		local ch = vim.fn.strcharpart(word, i, 1)
		if current ~= "" and display_width(current .. ch) > width then
			table.insert(lines, current)
			current = ch
		else
			current = current .. ch
		end
	end
	if current ~= "" then
		table.insert(lines, current)
	end
	return lines
end

local function wrap_text(value, width)
	value = tostring(value or "")
	if value == "" then
		return { "" }
	end
	local wrapped = {}
	for raw_line in (value .. "\n"):gmatch("([^\n]*)\n") do
		local current = ""
		if raw_line == "" then
			table.insert(wrapped, "")
		else
			for word in raw_line:gmatch("%S+") do
				if display_width(word) > width then
					if current ~= "" then
						table.insert(wrapped, current)
						current = ""
					end
					for _, part in ipairs(wrap_long_word(word, width)) do
						table.insert(wrapped, part)
					end
				else
					local candidate = current == "" and word or (current .. " " .. word)
					if display_width(candidate) <= width then
						current = candidate
					else
						table.insert(wrapped, current)
						current = word
					end
				end
			end
			if current ~= "" then
				table.insert(wrapped, current)
			end
		end
	end
	return #wrapped > 0 and wrapped or { "" }
end

local function has_draft_comment(thread)
	for _, comment in ipairs((thread and thread.comments) or {}) do
		if comment_status.is_draft(comment) then
			return true
		end
	end
	return false
end

local function thread_state(thread)
	if thread.state == "stale" or thread.is_outdated then
		return "stale"
	end
	if has_draft_comment(thread) then
		return "draft"
	end
	return thread.state or "open"
end

local function state_highlight(state)
	if state == "resolved" then
		return "UnifiedReviewInlineResolved"
	end
	if state == "draft" then
		return "UnifiedReviewInlineDraft"
	end
	if state == "stale" then
		return "UnifiedReviewInlineStale"
	end
	return "UnifiedReviewInlineOpen"
end

local function plural(count, singular, plural_word)
	return string.format("%d %s", count, count == 1 and singular or (plural_word or (singular .. "s")))
end

local function target_label(target)
	target = target or {}
	local line = target.start_line or target.line
	local end_line = target.line
	local label = target.side or target.start_side or "right"
	if line and end_line and end_line ~= line then
		return string.format("%s L%d-L%d", label, math.min(line, end_line), math.max(line, end_line))
	end
	if line then
		return string.format("%s L%d", label, line)
	end
	return label
end

local function window_text_width(win)
	local width = vim.api.nvim_win_get_width(win)
	local ok, info = pcall(vim.fn.getwininfo, win)
	local textoff = ok and info and info[1] and info[1].textoff or 0
	return math.max(1, width - textoff)
end

local function window_width_for_buffer(session, buf)
	local ui = session and session.ui or {}
	for _, win in ipairs({ ui.left_window, ui.right_window }) do
		if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
			return window_text_width(win)
		end
	end
	local wins = vim.fn.win_findbuf(buf)
	if wins and wins[1] and vim.api.nvim_win_is_valid(wins[1]) then
		return window_text_width(wins[1])
	end
	return 80
end

local function block_width_for(session, buf)
	local text_width = window_width_for_buffer(session, buf)
	return math.max(4, text_width - 4)
end

local function top_border(title, block_width)
	local rule_width = block_width - 2
	local label = " " .. truncate(title, math.max(1, rule_width - 2)) .. " "
	if display_width(label) > rule_width then
		label = truncate(label, rule_width)
	end
	return "┌" .. label .. fill_text("─", rule_width - display_width(label)) .. "┐"
end

local function bottom_border(block_width)
	return "└" .. fill_text("─", block_width - 2) .. "┘"
end

local function middle_line_chunks(text, inner_width, content_hl, border_hl)
	return {
		{ "│ ", border_hl or "UnifiedReviewInlineBorder" },
		{ pad_right(truncate(text or "", inner_width), inner_width), content_hl or "UnifiedReviewInlineBody" },
		{ " │", border_hl or "UnifiedReviewInlineBorder" },
	}
end

local function as_virt_line(text, hl)
	return { { text, hl or "UnifiedReviewInlineBody" } }
end

local function comment_meta(comment)
	local author = comment.author or "unknown"
	local state = comment.state and comment.state ~= "" and (" · " .. comment_status.draft_label(comment)) or ""
	return author .. state
end

local function thread_state_label(thread)
	if thread_state(thread) ~= "draft" then
		return thread_state(thread)
	end
	for _, comment in ipairs((thread and thread.comments) or {}) do
		if comment_status.is_local_draft(comment) then
			return "local draft"
		end
	end
	for _, comment in ipairs((thread and thread.comments) or {}) do
		if comment_status.is_remote_draft(comment) then
			return "remote draft"
		end
	end
	return "draft"
end

local function thread_title(thread)
	local state = thread_state(thread)
	local icon = STATE_ICONS[state] or STATE_ICONS.open
	local comments = thread.comments or {}
	local exported = review_thread.is_exported(thread) and "⇪ " or ""
	return string.format(
		"%s%s %s · %s · %s",
		exported,
		icon,
		thread_state_label(thread),
		plural(#comments, "comment"),
		target_label(thread.target)
	)
end

local function render_thread(thread, block_width)
	local inner_width = block_width - 4
	local lines = {}
	local state = thread_state(thread)
	local border_hl = state_highlight(state)
	table.insert(lines, as_virt_line(top_border(thread_title(thread), block_width), border_hl))
	local comments = thread.comments or {}
	if #comments == 0 then
		table.insert(lines, middle_line_chunks("No comments", inner_width, "UnifiedReviewInlineMeta", border_hl))
	else
		for index, comment in ipairs(comments) do
			if index > 1 then
				table.insert(lines, middle_line_chunks("", inner_width, "UnifiedReviewInlineBorder", border_hl))
			end
			table.insert(
				lines,
				middle_line_chunks(comment_meta(comment), inner_width, "UnifiedReviewInlineAuthor", border_hl)
			)
			for _, body_line in ipairs(wrap_text(comment.body or "", math.max(1, inner_width - 2))) do
				table.insert(
					lines,
					middle_line_chunks("  " .. body_line, inner_width, "UnifiedReviewInlineBody", border_hl)
				)
			end
		end
	end
	table.insert(lines, as_virt_line(bottom_border(block_width), border_hl))
	return lines
end

local function render_threads(threads, block_width)
	local lines = {}
	for index, thread in ipairs(threads or {}) do
		if index > 1 then
			table.insert(lines, as_virt_line("", "UnifiedReviewInlineBorder"))
		end
		vim.list_extend(lines, render_thread(thread, block_width))
	end
	return lines
end

local function filler_lines(count)
	local lines = {}
	for _ = 1, count do
		table.insert(lines, as_virt_line(FILLER_TEXT, FILLER_HL))
	end
	return lines
end

local function has_comment_text(lines)
	for _, line in ipairs(lines or {}) do
		for _, chunk in ipairs(line) do
			if chunk[2] ~= FILLER_HL and chunk[1] and chunk[1]:match("%S") then
				return true
			end
		end
	end
	return false
end

local function file_for_target(session, target)
	local current_file = require("unified_review.session.selection").current_file(session)
	if current_file and target.path == current_file.path then
		return current_file
	end
	for _, file in ipairs((session and session.files) or {}) do
		if target.path == file.path or target.path == file.old_path then
			return file
		end
	end
	return nil
end

local function current_file_matches(session, target)
	local current_file = require("unified_review.session.selection").current_file(session)
	return not current_file or target.path == current_file.path
end

local function opposite_side(side)
	return side == "left" and "right" or "left"
end

local function add_placement(placements, anchor, side, thread)
	local item = placements.by_key[anchor.key]
	if not item then
		item = { sides = {} }
		placements.by_key[anchor.key] = item
		table.insert(placements.items, item)
	end
	local above = anchor.above_by_side or { left = anchor.above, right = anchor.above }
	item.sides[side] = item.sides[side] or { row = anchor.rows[side], above = above[side], threads = {} }
	table.insert(item.sides[side].threads, thread)
	local other = opposite_side(side)
	if anchor.filler and anchor.filler.side == other then
		item.sides[other] = item.sides[other]
			or {
				row = anchor.filler.row,
				fallback_row = anchor.filler.fallback_row or anchor.rows[other],
				above = anchor.filler.above or false,
				mode = "filler",
				offset = anchor.filler.offset,
				threads = {},
			}
	else
		item.sides[other] = item.sides[other] or { row = anchor.rows[other], above = above[other], threads = {} }
	end
end

local function buffer_for_side(session, side)
	return side == "left" and session.ui.left_buffer or session.ui.right_buffer
end

local function valid_row_for_buffer(buf, row)
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return nil
	end
	local line_count = vim.api.nvim_buf_line_count(buf)
	if line_count <= 0 then
		return nil
	end
	return math.min(math.max(row, 0), line_count - 1)
end

local function line_for_side(line, side)
	return side == "left" and line.old_line or line.new_line
end

local function find_hunk_line(file, side, target_line)
	for hunk_index, hunk in ipairs(file.hunks or {}) do
		for line_index, line in ipairs(hunk.lines or {}) do
			if line_for_side(line, side) == target_line then
				return hunk, hunk_index, line, line_index
			end
		end
	end
	return nil
end

local function context_rows(line)
	if line and line.old_line and line.new_line then
		return { left = line.old_line - 1, right = line.new_line - 1 }
	end
	return nil
end

local function one_sided_block(hunk, line_index, kind)
	local start_index = line_index
	while start_index > 1 and hunk.lines[start_index - 1].kind == kind do
		start_index = start_index - 1
	end
	local end_index = line_index
	while hunk.lines[end_index + 1] and hunk.lines[end_index + 1].kind == kind do
		end_index = end_index + 1
	end
	return start_index, end_index
end

local function replacement_anchor(
	hunk_lines,
	hunk_index,
	line_index,
	side,
	line,
	block_start,
	block_end,
	other_start,
	other_end
)
	local other = opposite_side(side)
	local before_rows = context_rows(hunk_lines[math.min(block_start, other_start) - 1])
	if not before_rows then
		return nil
	end

	local target_offset = line_index - block_start + 1
	local current_count = block_end - block_start + 1
	local other_count = other_end - other_start + 1
	local other_filler_count = math.max(0, current_count - other_count)

	if target_offset <= other_filler_count then
		return {
			key = table.concat({ "hunk", hunk_index, line_index, side, "replacement-filler" }, ":"),
			rows = { left = line - 1, right = line - 1 },
			above = false,
			filler = {
				side = other,
				row = before_rows[other],
				fallback_row = before_rows[other],
				offset = target_offset,
			},
		}
	end

	local other_line = hunk_lines[other_start + target_offset - other_filler_count - 1]
	local other_row = other_line and line_for_side(other_line, other)
	if other_row then
		local rows = { left = line - 1, right = line - 1 }
		rows[other] = other_row - 1
		return {
			key = table.concat({ "hunk", hunk_index, line_index, side, "replacement-line" }, ":"),
			rows = rows,
			above = false,
		}
	end
	return nil
end

local function anchor_line_for_target(target)
	return target.line or target.start_line or 1
end

local function anchor_for_target(session, target)
	local side = target.side or target.start_side or "right"
	local line = anchor_line_for_target(target)
	local file = file_for_target(session, target)
	if target.kind == "file" then
		return {
			key = "file:" .. tostring(target.path or "") .. ":" .. tostring(side),
			rows = { left = 0, right = 0 },
			above = false,
		}
	end
	if not file or target.path ~= file.path then
		local row = line - 1
		return {
			key = table.concat({ "line", side, row, "below" }, ":"),
			rows = { left = row, right = row },
			above = false,
		}
	end

	local hunk, hunk_index, hunk_line, line_index = find_hunk_line(file, side, line)
	if hunk_line then
		local rows = context_rows(hunk_line)
		if rows then
			return {
				key = table.concat({ "hunk", hunk_index, line_index, "below" }, ":"),
				rows = rows,
				above = false,
			}
		end

		local block_start, block_end = one_sided_block(hunk, line_index, hunk_line.kind)
		local hunk_lines = hunk and hunk.lines or {}
		local other = opposite_side(side)
		local other_kind = hunk_line.kind == "added" and "deleted" or "added"
		if hunk_lines[block_start - 1] and hunk_lines[block_start - 1].kind == other_kind then
			local other_start, other_end = one_sided_block(hunk, block_start - 1, other_kind)
			local anchor = replacement_anchor(
				hunk_lines,
				hunk_index,
				line_index,
				side,
				line,
				block_start,
				block_end,
				other_start,
				other_end
			)
			if anchor then
				return anchor
			end
		end
		if hunk_lines[block_end + 1] and hunk_lines[block_end + 1].kind == other_kind then
			local other_start, other_end = one_sided_block(hunk, block_end + 1, other_kind)
			local anchor = replacement_anchor(
				hunk_lines,
				hunk_index,
				line_index,
				side,
				line,
				block_start,
				block_end,
				other_start,
				other_end
			)
			if anchor then
				return anchor
			end
		end
		local previous_rows = context_rows(hunk_lines[block_start - 1])
		if previous_rows then
			return {
				key = table.concat({ "hunk", hunk_index, line_index, side, "one-sided" }, ":"),
				rows = { left = line - 1, right = line - 1 },
				above = false,
				filler = {
					side = other,
					row = previous_rows[other],
					fallback_row = previous_rows[other],
					offset = line_index - block_start + 1,
				},
			}
		end
		local next_rows = context_rows(hunk_lines[block_end + 1])
		if next_rows then
			local start_rows = { left = line - 1, right = line - 1 }
			start_rows[other] = next_rows[other]
			return {
				key = table.concat({ "hunk", hunk_index, line_index, side, "one-sided-start" }, ":"),
				rows = start_rows,
				above = false,
				filler = {
					side = other,
					row = next_rows[other],
					fallback_row = next_rows[other],
					above = true,
					offset = line_index - block_start + 1,
				},
			}
		end
	end

	local row = line - 1
	return {
		key = table.concat({ "line", side, row, "below" }, ":"),
		rows = { left = row, right = row },
		above = false,
	}
end

local function sorted_placements(placements)
	return placements.items
end

local function codediff_filler_namespace()
	local ok, highlights = pcall(require, "codediff.ui.highlights")
	return ok and highlights and highlights.ns_filler or nil
end

local function codediff_highlight_namespace()
	local ok, highlights = pcall(require, "codediff.ui.highlights")
	return ok and highlights and highlights.ns_highlight or nil
end

local function restore_filler_patches(session)
	local ns = codediff_filler_namespace()
	if not ns then
		return
	end
	for _, patch in ipairs((session and session._inline_filler_patches) or {}) do
		if patch.buf and vim.api.nvim_buf_is_valid(patch.buf) then
			vim.api.nvim_buf_clear_namespace(patch.buf, ns, patch.row, patch.row + 1)
			for _, mark in ipairs(patch.original_marks or {}) do
				vim.api.nvim_buf_set_extmark(patch.buf, ns, mark.row, 0, {
					virt_lines = mark.virt_lines,
					virt_lines_above = mark.virt_lines_above,
				})
			end
		end
	end
	if session then
		session._inline_filler_patches = nil
	end
end

local function add_virtual_line_patch(patches, buf, row, offset, lines)
	if not (buf and row and offset and lines and #lines > 0) then
		return
	end
	local key = tostring(buf) .. ":" .. tostring(row)
	patches[key] = patches[key] or { buf = buf, row = row, insertions = {} }
	local insertions = patches[key].insertions
	table.insert(insertions, { offset = offset, lines = vim.deepcopy(lines), seq = #insertions + 1 })
end

local function virtual_line_marks(buf, namespaces)
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return {}
	end
	local marks = {}
	for _, ns in ipairs(namespaces or {}) do
		if ns then
			for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
				local details = mark[4] or {}
				if details.virt_lines then
					table.insert(marks, {
						row = mark[2],
						above = details.virt_lines_above == true,
						count = #details.virt_lines,
					})
				end
			end
		end
	end
	table.sort(marks, function(left, right)
		if left.row == right.row then
			return left.above and not right.above
		end
		return left.row < right.row
	end)
	return marks
end

local function filler_marks(buf)
	return virtual_line_marks(buf, { codediff_filler_namespace() })
end

local function visual_marks(buf)
	return virtual_line_marks(buf, { codediff_filler_namespace(), codediff_highlight_namespace() })
end

local function has_filler_mark(buf, row)
	if not row then
		return false
	end
	for _, mark in ipairs(filler_marks(buf)) do
		if mark.row == row then
			return true
		end
	end
	return false
end

local function visual_before_line(buf, row)
	local visual = row
	for _, mark in ipairs(visual_marks(buf)) do
		if mark.row < row or (mark.row == row and mark.above) then
			visual = visual + mark.count
		end
	end
	return visual
end

local function visual_after_line(buf, row)
	return visual_before_line(buf, row) + 1
end

local function resolve_filler_patch_at_visual_row(buf, visual_row)
	for _, mark in ipairs(filler_marks(buf)) do
		local start
		if mark.above then
			start = visual_before_line(buf, mark.row) - mark.count
		else
			start = visual_after_line(buf, mark.row)
		end
		if visual_row >= start and visual_row <= start + mark.count then
			return mark.row, math.max(0, visual_row - start)
		end
	end
	return nil, nil
end

local function align_filler_placements_to_visual_rows(session, item)
	for _, side in ipairs({ "left", "right" }) do
		local target_placement = item.sides[side]
		local other = opposite_side(side)
		local spacer_placement = item.sides[other]
		if target_placement and #(target_placement.threads or {}) > 0 and spacer_placement then
			local target_buf = buffer_for_side(session, side)
			local target_row = valid_row_for_buffer(target_buf, target_placement.row)
			local spacer_buf = buffer_for_side(session, other)
			if target_row and spacer_buf and vim.api.nvim_buf_is_valid(spacer_buf) then
				local row, offset =
					resolve_filler_patch_at_visual_row(spacer_buf, visual_after_line(target_buf, target_row))
				if row and #(spacer_placement.threads or {}) == 0 then
					spacer_placement.mode = "filler"
					spacer_placement.row = row
					spacer_placement.fallback_row = row
					spacer_placement.offset = offset
					spacer_placement.above = false
				end
			end
		end
	end
end

local function apply_filler_patches(session, patches)
	local ns = codediff_filler_namespace()
	if not ns then
		return
	end
	session._inline_filler_patches = {}
	for _, patch in pairs(patches) do
		if patch.buf and vim.api.nvim_buf_is_valid(patch.buf) then
			local marks = vim.api.nvim_buf_get_extmarks(patch.buf, ns, 0, -1, { details = true })
			local original_marks = {}
			local filler_mark
			for _, mark in ipairs(marks) do
				local details = mark[4] or {}
				if mark[2] == patch.row and details.virt_lines then
					table.insert(original_marks, {
						row = mark[2],
						virt_lines = details.virt_lines,
						virt_lines_above = details.virt_lines_above,
					})
					filler_mark = filler_mark or details
				end
			end
			if filler_mark then
				table.insert(
					session._inline_filler_patches,
					{ buf = patch.buf, row = patch.row, original_marks = original_marks }
				)
				local lines = vim.deepcopy(filler_mark.virt_lines or {})
				table.sort(patch.insertions, function(left, right)
					if left.offset == right.offset then
						return left.seq > right.seq
					end
					return left.offset > right.offset
				end)
				for _, insertion in ipairs(patch.insertions) do
					local insert_at = math.min(math.max(insertion.offset, 0), #lines)
					for index = #(insertion.lines or {}), 1, -1 do
						table.insert(lines, insert_at + 1, insertion.lines[index])
					end
				end
				vim.api.nvim_buf_clear_namespace(patch.buf, ns, patch.row, patch.row + 1)
				vim.api.nvim_buf_set_extmark(patch.buf, ns, patch.row, 0, {
					virt_lines = lines,
					virt_lines_above = filler_mark.virt_lines_above,
				})
			end
		end
	end
end

local function append_comment_extmarks(filtered, buf, ns)
	if not ns then
		return
	end
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
		if has_comment_text(mark[4] and mark[4].virt_lines) then
			table.insert(filtered, mark)
		end
	end
end

local function comment_extmarks(buf)
	local filtered = {}
	append_comment_extmarks(filtered, buf, inline_ns)
	append_comment_extmarks(filtered, buf, codediff_filler_namespace())
	table.sort(filtered, function(left, right)
		return left[2] < right[2]
	end)
	return filtered
end

--- Place virtual-line thread blocks for all visible threads in the session.
function M.place(session)
	if not session or not session.ui then
		return
	end
	ensure_highlights()
	M.clear(session)

	session._inline_visible = true
	local placements = { items = {}, by_key = {} }
	for _, thread in ipairs(session.threads or {}) do
		local target = thread.target or {}
		if current_file_matches(session, target) then
			local side = target.side or target.start_side or "right"
			local buf = buffer_for_side(session, side)
			if buf and vim.api.nvim_buf_is_valid(buf) then
				local line = anchor_line_for_target(target)
				local line_count = vim.api.nvim_buf_line_count(buf)
				if target.kind == "file" or (line > 0 and line <= line_count) then
					add_placement(placements, anchor_for_target(session, target), side, thread)
				end
			end
		end
	end

	local filler_patches = {}
	for _, item in ipairs(sorted_placements(placements)) do
		align_filler_placements_to_visual_rows(session, item)
		local rendered = {}
		local height = 0
		for _, side in ipairs({ "left", "right" }) do
			local side_placement = item.sides[side]
			if side_placement and #side_placement.threads > 0 then
				local buf = buffer_for_side(session, side)
				local block_width = buf and vim.api.nvim_buf_is_valid(buf) and block_width_for(session, buf) or 80
				rendered[side] = render_threads(side_placement.threads, block_width)
				height = math.max(height, #rendered[side])
			end
		end
		if height > 0 then
			for _, side in ipairs({ "left", "right" }) do
				local side_placement = item.sides[side]
				local buf = buffer_for_side(session, side)
				local mark_row = side_placement and valid_row_for_buffer(buf, side_placement.row)
				if mark_row then
					local lines = vim.deepcopy(rendered[side] or filler_lines(height))
					if #lines < height then
						vim.list_extend(lines, filler_lines(height - #lines))
					end

					if has_filler_mark(buf, mark_row) then
						add_virtual_line_patch(filler_patches, buf, mark_row, side_placement.offset or 0, lines)
					else
						local spacer_row = side_placement.mode == "filler"
								and valid_row_for_buffer(buf, side_placement.fallback_row)
							or mark_row
						if spacer_row then
							vim.api.nvim_buf_set_extmark(buf, inline_ns, spacer_row, 0, {
								virt_lines = lines,
								virt_lines_above = side_placement.above,
								virt_lines_leftcol = false,
								virt_lines_overflow = "trunc",
								priority = 10,
							})
						end
					end
				end
			end
		end
	end
	apply_filler_patches(session, filler_patches)
end

--- Clear all inline thread blocks for a session.
function M.clear(session)
	if not session or not session.ui then
		return
	end
	restore_filler_patches(session)
	for _, buf in ipairs({ session.ui.left_buffer, session.ui.right_buffer }) do
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_clear_namespace(buf, inline_ns, 0, -1)
		end
	end
end

--- Navigate to the next inline comment in the given buffer.
function M.next_inline(buf, cursor_row)
	buf = buf or vim.api.nvim_get_current_buf()
	local marks = comment_extmarks(buf)
	if #marks == 0 then
		return nil
	end
	cursor_row = cursor_row or (vim.api.nvim_win_get_cursor(0)[1] - 1)
	for _, mark in ipairs(marks) do
		local row = mark[2]
		if row > cursor_row then
			return row + 1
		end
	end
	return marks[1][2] + 1
end

--- Navigate to the previous inline comment in the given buffer.
function M.previous_inline(buf, cursor_row)
	buf = buf or vim.api.nvim_get_current_buf()
	local marks = comment_extmarks(buf)
	if #marks == 0 then
		return nil
	end
	cursor_row = cursor_row or (vim.api.nvim_win_get_cursor(0)[1] - 1)
	for i = #marks, 1, -1 do
		local row = marks[i][2]
		if row < cursor_row then
			return row + 1
		end
	end
	return marks[#marks][2] + 1
end

return M
