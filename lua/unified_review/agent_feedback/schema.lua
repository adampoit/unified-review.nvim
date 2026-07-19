local comment_target = require("unified_review.domain.comment_target")

local M = {}

local SCHEMA = "unified-review.agent-feedback.v1"

local function err(message)
	return nil, { message = message }
end

local function is_array(value)
	local islist = vim.islist or vim.tbl_islist
	return type(value) == "table" and islist(value)
end

local function validate_optional_string(value, field)
	if value ~= nil and type(value) ~= "string" then
		return err(field .. " must be a string")
	end
	return true, nil
end

local function validate_source(source)
	if source == nil then
		return true, nil
	end
	if type(source) ~= "table" or is_array(source) then
		return err("source must be an object")
	end
	if type(source.name) ~= "string" then
		return err("source.name is required")
	end
	local _, run_err = validate_optional_string(source.run_id, "source.run_id")
	if run_err then
		return nil, run_err
	end
	return validate_optional_string(source.model, "source.model")
end

local function validate_comment(raw, index)
	if type(raw) ~= "table" then
		return err("comments[" .. index .. "] must be an object")
	end
	if type(raw.body) ~= "string" or raw.body == "" then
		return err("comments[" .. index .. "].body is required")
	end
	for _, field in ipairs({ "id", "author", "category" }) do
		local _, field_err = validate_optional_string(raw[field], "comments[" .. index .. "]." .. field)
		if field_err then
			return nil, field_err
		end
	end
	if raw.severity ~= nil and not vim.tbl_contains({ "error", "warning", "info", "nit" }, raw.severity) then
		return err("comments[" .. index .. "].severity is invalid")
	end
	if type(raw.target) ~= "table" then
		return err("comments[" .. index .. "].target is required")
	end
	local ok, target_or_err = pcall(comment_target.new, raw.target)
	if not ok then
		return err("comments[" .. index .. "].target is invalid: " .. tostring(target_or_err))
	end
	local normalized = vim.deepcopy(raw)
	normalized.target = target_or_err
	return normalized, nil
end

function M.validate(review)
	if type(review) ~= "table" then
		return err("agent feedback must be a JSON object")
	end
	if review.schema ~= SCHEMA then
		return err("unsupported agent feedback schema: " .. tostring(review.schema))
	end
	for _, field in ipairs({ "author", "summary" }) do
		local _, field_err = validate_optional_string(review[field], field)
		if field_err then
			return nil, field_err
		end
	end
	local _, source_err = validate_source(review.source)
	if source_err then
		return nil, source_err
	end
	if review.comments ~= nil and not is_array(review.comments) then
		return err("comments must be an array")
	end
	local normalized = vim.deepcopy(review)
	normalized.comments = {}
	for index, comment in ipairs(review.comments or {}) do
		local validated, comment_err = validate_comment(comment, index)
		if not validated then
			return nil, comment_err
		end
		table.insert(normalized.comments, validated)
	end
	return normalized, nil
end

M.SCHEMA = SCHEMA

return M
