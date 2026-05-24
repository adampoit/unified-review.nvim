local M = {}

function M.content_anchor(opts)
	opts = opts or {}
	return {
		hunk_header = opts.hunk_header,
		before = opts.before or {},
		selected = opts.selected or {},
		after = opts.after or {},
		base_id = opts.base_id,
		head_id = opts.head_id,
		excerpt_hash = vim.fn.sha256(table.concat(opts.selected or {}, "\n")),
	}
end

return M
