local M = {}

function M.make(kind, fields)
	fields = fields or {}
	fields._ur_component = true
	fields.kind = kind
	return fields
end

return M
