local ids = require("unified_review.domain.ids")
local target = require("unified_review.domain.comment_target")
local validate = require("unified_review.domain.validation")

local M = {}

function M.new(opts)
	opts = opts or {}
	return {
		id = opts.id or ids.new("comment"),
		thread_id = opts.thread_id,
		body = validate.required(opts.body, "body"),
		author = opts.author or vim.env.USER or "local",
		created_at = opts.created_at or os.date("!%Y-%m-%dT%H:%M:%SZ"),
		updated_at = opts.updated_at,
		state = opts.state or "draft",
		target = opts.target and target.new(opts.target) or nil,
		metadata = opts.metadata or {},
	}
end

return M
