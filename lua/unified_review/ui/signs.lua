local comment_status = require("unified_review.domain.comment_status")
local review_thread = require("unified_review.domain.review_thread")

local M = {}

local namespace = "unified_review_threads"
local legacy_diff_namespace = "unified_review_diff"

-- devicon glyphs for each thread state
local sign_icons = {
	UnifiedReviewThread = { icon = "󰆉", hl = "UnifiedReviewThread" },
	UnifiedReviewResolved = { icon = "󰄬", hl = "UnifiedReviewResolved" },
	UnifiedReviewDraft = { icon = "󰙏", hl = "UnifiedReviewDraft" },
	UnifiedReviewRemoteDraft = { icon = "󰖟", hl = "UnifiedReviewDraft" },
	UnifiedReviewStale = { icon = "󰀦", hl = "UnifiedReviewStale" },
	UnifiedReviewSuggestion = { icon = "󰌵", hl = "UnifiedReviewSuggestion" },
	UnifiedReviewExported = { icon = "⇪", hl = "UnifiedReviewSuggestion" },
	UnifiedReviewRangeTop = { icon = "┌", hl = "UnifiedReviewThread" },
	UnifiedReviewRangeMid = { icon = "│", hl = "UnifiedReviewThread" },
	UnifiedReviewRangeBot = { icon = "└", hl = "UnifiedReviewThread" },
}

-- range bracket glyphs for multi-line comments
local range_icons = {
	top = "┌",
	mid = "│",
	bot = "└",
}

local extmark_ns = vim.api.nvim_create_namespace("unified_review_threads")

local function define(name, opts)
	pcall(vim.fn.sign_define, name, opts)
end

function M.setup()
	for name, info in pairs(sign_icons) do
		define(name, { text = info.icon, texthl = info.hl })
	end
end

local function sign_for(thread)
	if thread.state == "stale" or thread.is_outdated then
		return "UnifiedReviewStale"
	end
	if thread.state == "resolved" then
		return "UnifiedReviewResolved"
	end
	local has_remote_draft = false
	for _, comment in ipairs(thread.comments or {}) do
		if comment_status.is_local_draft(comment) then
			return "UnifiedReviewDraft"
		end
		if comment_status.is_remote_draft(comment) then
			has_remote_draft = true
		end
	end
	if has_remote_draft then
		return "UnifiedReviewRemoteDraft"
	end
	return "UnifiedReviewThread"
end

--- Build the range bracket glyph for the given position in a range.
local function range_bracket(index, total)
	if total <= 1 then
		return nil
	end
	if index == 1 then
		return range_icons.top
	elseif index == total then
		return range_icons.bot
	end
	return range_icons.mid
end

local function thread_rows(session, thread, side)
	local target = thread.target or {}
	local file = require("unified_review.session.selection").current_file(session)
	if not file or target.path ~= file.path then
		return {}
	end
	if target.kind == "file" then
		return { 1 }
	end
	if target.side and target.side ~= side then
		return {}
	end
	if target.start_side and target.start_side ~= side then
		return {}
	end
	local start_line = target.start_line or target.line
	local end_line = target.line or target.start_line
	if not start_line or not end_line then
		return {}
	end
	local rows = {}
	for row = math.min(start_line, end_line), math.max(start_line, end_line) do
		table.insert(rows, row)
	end
	return rows
end

function M.clear(session)
	if not session or not session.ui then
		return
	end
	for _, buf in ipairs({ session.ui.left_buffer, session.ui.right_buffer }) do
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.fn.sign_unplace(namespace, { buffer = buf })
			vim.fn.sign_unplace(legacy_diff_namespace, { buffer = buf })
			vim.api.nvim_buf_clear_namespace(buf, extmark_ns, 0, -1)
		end
	end
end

function M.place(session)
	if not session or not session.ui then
		return
	end
	M.setup()
	M.clear(session)
	local sign_id = 1
	for _, thread in ipairs(session.threads or {}) do
		for _, side in ipairs({ "left", "right" }) do
			local rows = thread_rows(session, thread, side)
			local buf = side == "left" and session.ui.left_buffer or session.ui.right_buffer
			if buf and vim.api.nvim_buf_is_valid(buf) then
				local total = #rows
				for index, row in ipairs(rows) do
					if index == 1 and review_thread.is_exported(thread) then
						vim.fn.sign_place(
							sign_id,
							namespace,
							"UnifiedReviewExported",
							buf,
							{ lnum = row, priority = 25 }
						)
						sign_id = sign_id + 1
					end
					-- Pick the right sign: normal icon for single-line threads,
					-- range brackets for multi-line threads.
					local sign_name
					if total == 1 then
						sign_name = sign_for(thread)
					else
						local bracket = range_bracket(index, total)
						if bracket == range_icons.top then
							sign_name = "UnifiedReviewRangeTop"
						elseif bracket == range_icons.mid then
							sign_name = "UnifiedReviewRangeMid"
						else
							sign_name = "UnifiedReviewRangeBot"
						end
					end
					vim.fn.sign_place(sign_id, namespace, sign_name, buf, { lnum = row, priority = 20 })

					sign_id = sign_id + 1
				end
			end
		end
	end
end

return M
