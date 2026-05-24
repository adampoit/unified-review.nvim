local validate = require("unified_review.domain.validation")

local M = {}

M.sides = { "left", "right" }
M.kinds = { "line", "range", "file" }

function M.line(opts)
	opts = opts or {}
	return {
		kind = "line",
		path = validate.required(opts.path, "path"),
		side = validate.one_of(opts.side, "side", M.sides),
		line = validate.required(opts.line, "line"),
	}
end

function M.range(opts)
	opts = opts or {}
	return {
		kind = "range",
		path = validate.required(opts.path, "path"),
		start_line = validate.required(opts.start_line, "start_line"),
		start_side = validate.one_of(opts.start_side, "start_side", M.sides),
		line = validate.required(opts.line, "line"),
		side = validate.one_of(opts.side, "side", M.sides),
	}
end

function M.file(opts)
	opts = opts or {}
	return {
		kind = "file",
		path = validate.required(opts.path, "path"),
	}
end

function M.new(opts)
	opts = opts or {}
	local kind = validate.one_of(opts.kind, "kind", M.kinds)
	if kind == "line" then
		return M.line(opts)
	elseif kind == "range" then
		return M.range(opts)
	end
	return M.file(opts)
end

function M.equals(left, right)
	if left == nil or right == nil or left.kind ~= right.kind or left.path ~= right.path then
		return false
	end
	if left.kind == "file" then
		return true
	end
	if left.kind == "line" then
		return left.side == right.side and left.line == right.line
	end
	return left.start_line == right.start_line
		and left.start_side == right.start_side
		and left.line == right.line
		and left.side == right.side
end

function M.label(target)
	if target.kind == "file" then
		return target.path
	end
	if target.kind == "line" then
		return string.format("%s:%s:%s", target.path, target.side, target.line)
	end
	return string.format("%s:%s:%s-%s:%s", target.path, target.start_side, target.start_line, target.side, target.line)
end

return M
