local M = {}

function M.required(value, field)
	if value == nil or value == "" then
		error(field .. " is required", 3)
	end
	return value
end

function M.one_of(value, field, allowed)
	M.required(value, field)
	for _, candidate in ipairs(allowed) do
		if value == candidate then
			return value
		end
	end
	error(field .. " must be one of: " .. table.concat(allowed, ", "), 3)
end

function M.list(value)
	if value == nil then
		return {}
	end
	if type(value) ~= "table" then
		error("expected list table", 3)
	end
	return value
end

return M
