local validate = require("unified_review.domain.validation")

local M = {}

M.kinds = { "context", "added", "deleted", "header" }

function M.new(opts)
	opts = opts or {}
	return {
		kind = validate.one_of(opts.kind, "kind", M.kinds),
		old_line = opts.old_line,
		new_line = opts.new_line,
		text = opts.text or "",
		raw = opts.raw or opts.text or "",
		metadata = opts.metadata or {},
	}
end

return M
