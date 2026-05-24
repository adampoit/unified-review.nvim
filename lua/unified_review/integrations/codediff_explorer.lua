local state = require("unified_review.session.state")

local M = {}

local installed = false

local function thread_counts(session, path)
	local counts = { open = 0, draft = 0, stale = 0, resolved = 0 }
	for _, thread in ipairs(session.threads or {}) do
		if thread.target and thread.target.path == path then
			if thread.state == "stale" or thread.is_outdated then
				counts.stale = counts.stale + 1
			elseif thread.state == "resolved" then
				counts.resolved = counts.resolved + 1
			else
				counts.open = counts.open + 1
			end
			for _, comment in ipairs(thread.comments or {}) do
				if comment.state == "draft" then
					counts.draft = counts.draft + 1
				end
			end
		end
	end
	return counts
end

local function is_file_resolved(session, path)
	local counts = thread_counts(session, path)
	local total = counts.open + counts.draft + counts.stale + counts.resolved
	return total > 0 and counts.resolved == total
end

local function viewed_marker(session, path)
	if not session or not path then
		return nil
	end
	if not (session.viewed_files and session.viewed_files[path]) then
		return "●", "CodeDiffExplorerReviewUnviewed"
	end
	if is_file_resolved(session, path) then
		return "✓", "CodeDiffExplorerReviewResolved"
	end
	return " ", "Normal"
end

local function define_highlights()
	vim.api.nvim_set_hl(0, "CodeDiffExplorerReviewUnviewed", { default = true, fg = "#e5c07b" })
	vim.api.nvim_set_hl(0, "CodeDiffExplorerReviewResolved", { default = true, fg = "#98c379" })
end

function M.install()
	if installed then
		return true
	end
	local ok, nodes = pcall(require, "codediff.ui.explorer.nodes")
	if not ok or type(nodes.prepare_node) ~= "function" then
		return false
	end

	define_highlights()
	local original_prepare_node = nodes.prepare_node
	nodes.prepare_node = function(node, max_width, ...)
		local data = node and node.data or {}
		local marker, hl = viewed_marker(state.get_active(), data.path)
		local line = original_prepare_node(node, marker and math.max(1, (max_width or 1) - 2) or max_width, ...)
		if not (line and line._segments and marker) then
			return line
		end
		table.insert(line._segments, 1, { text = marker .. " ", hl = hl })
		return line
	end
	installed = true
	return true
end

function M.refresh(tabpage)
	local ok_lifecycle, lifecycle = pcall(require, "codediff.ui.lifecycle")
	if not ok_lifecycle then
		return
	end
	local session = lifecycle.get_session(tabpage or vim.api.nvim_get_current_tabpage())
	local explorer = session and session.explorer
	if explorer and explorer.tree then
		pcall(explorer.tree.render, explorer.tree)
	end
end

return M
