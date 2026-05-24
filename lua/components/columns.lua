local make = require("components.component").make

local M = {}

function M.component(cells, opts)
	return make("columns", { cells = cells or {}, opts = opts or {} })
end

return M
