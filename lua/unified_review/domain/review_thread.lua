local ids = require("unified_review.domain.ids")
local target = require("unified_review.domain.comment_target")
local validate = require("unified_review.domain.validation")

local M = {}

M.states = { "open", "action_required", "waiting_review", "resolved", "stale" }

local function has_draft_comment(thread)
	for _, comment in ipairs((thread and thread.comments) or {}) do
		if comment.state == "draft" then
			return true
		end
	end
	return false
end

function M.new(opts)
	opts = opts or {}
	return {
		id = opts.id or ids.new("thread"),
		target = target.new(validate.required(opts.target, "target")),
		comments = validate.list(opts.comments),
		state = validate.one_of(opts.state or "open", "state", M.states),
		is_outdated = opts.is_outdated or false,
		metadata = opts.metadata or {},
	}
end

function M.is_stale(thread)
	return thread ~= nil and (thread.state == "stale" or thread.is_outdated == true)
end

function M.is_exported(thread)
	local metadata = thread and thread.metadata or {}
	if metadata.export ~= nil then
		return metadata.export == true
	end
	return has_draft_comment(thread)
end

function M.set_exported(thread, exported)
	if not thread then
		return nil
	end
	thread.metadata = thread.metadata or {}
	thread.metadata.export = exported == true
	return thread
end

function M.toggle_exported(thread)
	return M.set_exported(thread, not M.is_exported(thread))
end

function M.mark_draft_exports(threads)
	for _, thread in ipairs(threads or {}) do
		if thread.metadata == nil then
			thread.metadata = {}
		end
		if thread.metadata.export == nil and has_draft_comment(thread) then
			thread.metadata.export = true
		end
	end
	return threads
end

return M
