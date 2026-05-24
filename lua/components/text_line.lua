local make = require("components.component").make

local M = {}

function M.component(value, hl)
	return make("text_line", { value = tostring(value or ""), hl = hl })
end

return M
