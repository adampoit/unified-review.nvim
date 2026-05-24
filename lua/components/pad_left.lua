local make = require("components.component").make

local M = {}

function M.component(child, width, opts)
	opts = opts or {}
	return make("pad_left", { child = child, width = width, fill = opts.fill, hl = opts.hl })
end

return M
