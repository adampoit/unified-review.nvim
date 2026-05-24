local M = {}

M.current_version = 1

function M.migrate(data)
	data = data or {}
	data.version = data.version or 1
	if data.version > M.current_version then
		return nil, { message = "unsupported session store version: " .. tostring(data.version) }
	end
	return data, nil
end

return M
