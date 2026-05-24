local make = require("components.component").make

local M = {}

function M.component(width, opts)
	opts = opts or {}
	return make("space", { width = width or 1, hl = opts.hl })
end

return M
