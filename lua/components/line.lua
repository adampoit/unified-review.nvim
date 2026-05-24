local make = require("components.component").make

local M = {}

function M.component(children, opts)
	return make("line", { children = children or {}, opts = opts or {} })
end

return M
