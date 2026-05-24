local validate = require("unified_review.domain.validation")

local M = {}

function M.new(opts)
	opts = opts or {}
	return {
		header = validate.required(opts.header, "header"),
		old_start = validate.required(opts.old_start, "old_start"),
		old_count = opts.old_count or 0,
		new_start = validate.required(opts.new_start, "new_start"),
		new_count = opts.new_count or 0,
		lines = validate.list(opts.lines),
		metadata = opts.metadata or {},
	}
end

return M
