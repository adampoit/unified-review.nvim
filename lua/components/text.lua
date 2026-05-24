local make = require("components.component").make

local M = {}

function M.component(value, hl)
	return make("text", { value = tostring(value or ""), hl = hl })
end

return M
