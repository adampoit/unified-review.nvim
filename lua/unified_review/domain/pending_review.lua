local ids = require("unified_review.domain.ids")
local validate = require("unified_review.domain.validation")

local M = {}

M.states = { "draft", "submitted" }

function M.new(opts)
	opts = opts or {}
	return {
		id = opts.id or ids.new("review"),
		target = validate.required(opts.target, "target"),
		threads = validate.list(opts.threads),
		comments = validate.list(opts.comments),
		state = validate.one_of(opts.state or "draft", "state", M.states),
		metadata = opts.metadata or {},
	}
end

return M
