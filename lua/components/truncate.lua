local make = require("components.component").make

local M = {}

function M.component(child, width, opts)
	opts = opts or {}
	return make("truncate", { child = child, width = width, hl = opts.hl })
end

return M
