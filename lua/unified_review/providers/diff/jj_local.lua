local jj = require("unified_review.integrations.jj")
local parser = require("unified_review.util.patch_parse")

local M = {}

function M.open(target)
	target = target or {}
	local resolved, resolve_err = jj.resolve_target(target, target.cwd or target.root)
	if not resolved then
		return nil, resolve_err
	end

	local patch_result = jj.patch(resolved)
	if not patch_result.ok then
		return nil, patch_result
	end

	return {
		provider = "jj_local",
		target = resolved,
		files = parser.parse(patch_result.stdout),
		raw_patch = patch_result.stdout,
		editable = false,
	},
		nil
end

function M.refresh(session)
	return M.open(session.target)
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
