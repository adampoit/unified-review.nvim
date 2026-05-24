local config = require("unified_review.config")
local git = require("unified_review.integrations.git")
local parser = require("unified_review.util.patch_parse")

local M = {}

local function target_refs(target)
	target = target or {}
	local defaults = config.options.local_git or config.defaults.local_git
	local base = target.base or target.base_ref
	local head = target.head or target.head_ref or defaults.head_ref
	if not base then
		base = git.infer_default_branch(target.cwd, defaults.base_ref)
	end
	return base, head, target.range_kind or "three_dot"
end

function M.open(target)
	target = target or {}
	local base, head, range_kind = target_refs(target)
	local cwd = target.cwd or target.git_root or target.root
	local resolved, resolve_err = git.resolve_target({ base = base, head = head, range_kind = range_kind }, cwd)
	if not resolved then
		return nil, resolve_err
	end
	---@cast resolved table
	resolved = vim.tbl_extend("force", vim.deepcopy(target), resolved)
	---@cast resolved table

	local patch_base = resolved.head_oid == "WORKING" and resolved.base_oid or base
	local patch_head = resolved.head or head
	local patch_root = resolved.root or cwd
	local patch_range_kind = resolved.range_kind or range_kind
	if not patch_base or not patch_head or not patch_root then
		return nil, { message = "Unable to resolve Git diff endpoints" }
	end
	local patch_result = git.patch(patch_base, patch_head, patch_root, patch_range_kind)
	if not patch_result.ok then
		return nil, patch_result
	end

	return {
		provider = "git_local",
		target = resolved,
		files = parser.parse(patch_result.stdout),
		raw_patch = patch_result.stdout,
		editable = resolved.editable ~= false and resolved.head_oid == "WORKING",
	},
		nil
end

function M.refresh(session)
	return M.open({
		cwd = session.target.root,
		base = session.target.base,
		head = session.target.head,
		range_kind = session.target.range_kind,
	})
end

function M.get_file(session, path)
	for _, file in ipairs(session.files or {}) do
		if file.path == path or file.old_path == path then
			return file
		end
	end
	return nil
end

---@diagnostic disable-next-line: unused-local
function M.map_visual_range(session, path, start_row, end_row, side)
	if start_row == end_row then
		return { kind = "line", path = path, side = side, line = start_row }
	end
	return {
		kind = "range",
		path = path,
		start_side = side,
		start_line = start_row,
		side = side,
		line = end_row,
	}
end

return M
