--- Session status summary for tabline and :UnifiedReview status.
local comment_status = require("unified_review.domain.comment_status")

local M = {}

function M.summary(session)
	if not session then
		return nil
	end
	local files = #(session.files or {})
	local threads = #(session.threads or {})
	local drafts = 0
	local local_drafts = 0
	local remote_drafts = 0
	local open_threads = 0
	local stale = 0
	for _, t in ipairs(session.threads or {}) do
		if t.state == "stale" or t.is_outdated then
			stale = stale + 1
		elseif t.state ~= "resolved" then
			open_threads = open_threads + 1
		end
		for _, c in ipairs(t.comments or {}) do
			if comment_status.is_draft(c) then
				drafts = drafts + 1
				if comment_status.is_local_draft(c) then
					local_drafts = local_drafts + 1
				elseif comment_status.is_remote_draft(c) then
					remote_drafts = remote_drafts + 1
				end
			end
		end
	end
	return {
		files = files,
		threads = threads,
		open = open_threads,
		drafts = drafts,
		local_drafts = local_drafts,
		remote_drafts = remote_drafts,
		stale = stale,
	}
end

--- Format a one-line status string for :UnifiedReview status or tabline.
function M.format(session, style)
	local s = M.summary(session)
	if not s then
		return "unified-review: no active session"
	end
	style = style or "full"
	if style == "compact" then
		local badges = {}
		if s.open > 0 then
			table.insert(badges, "T" .. s.open)
		end
		if s.drafts > 0 then
			table.insert(badges, "D" .. s.drafts)
		end
		if s.stale > 0 then
			table.insert(badges, "S" .. s.stale)
		end
		return string.format("Review │ %df", s.files)
			.. (#badges > 0 and (" │ " .. table.concat(badges, " ")) or "")
	end
	local parts = { "Review" }
	if session.target then
		local ref = session.target.base_ref or session.target.base or "?"
		table.insert(parts, ref .. "..HEAD")
	end
	table.insert(parts, string.format("%d file(s)", s.files))
	local badges = {}
	if s.open > 0 then
		table.insert(badges, "T" .. s.open)
	end
	if s.drafts > 0 then
		table.insert(badges, "D" .. s.drafts)
	end
	if s.stale > 0 then
		table.insert(badges, "S" .. s.stale)
	end
	if #badges > 0 then
		table.insert(parts, table.concat(badges, " "))
	end
	return table.concat(parts, " │ ")
end

--- Set the review tab's label variable for tabline plugins to read.
function M.set_tab_label(tabpage, session)
	tabpage = tabpage or vim.api.nvim_get_current_tabpage()
	local style = require("unified_review.config").options.ui.tabline_format
	if style == false then
		return
	end
	local label = M.format(session, style)
	if label then
		vim.api.nvim_tabpage_set_var(tabpage, "review_label", label)
	end
end

return M
