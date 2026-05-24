local M = {}

function M.hunk_lines(hunk)
	local rows = {}
	for index, line in ipairs(hunk.lines or {}) do
		rows[index] = {
			kind = line.kind,
			old_line = line.old_line,
			new_line = line.new_line,
		}
	end
	return rows
end

return M
