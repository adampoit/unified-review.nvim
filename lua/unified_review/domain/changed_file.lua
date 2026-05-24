local validate = require("unified_review.domain.validation")

local M = {}

M.statuses = { "added", "modified", "deleted", "renamed", "copied", "type_changed", "binary" }

function M.new(opts)
	opts = opts or {}
	return {
		path = validate.required(opts.path, "path"),
		old_path = opts.old_path,
		status = validate.one_of(opts.status or "modified", "status", M.statuses),
		additions = opts.additions or 0,
		deletions = opts.deletions or 0,
		hunks = validate.list(opts.hunks),
		raw_patch = opts.raw_patch or "",
		metadata = opts.metadata or {},
	}
end

return M
