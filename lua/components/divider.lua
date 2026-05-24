local make = require("components.component").make

local M = {}

function M.component(width, opts)
	opts = opts or {}
	return make("divider", { width = width, hl = opts.hl })
end

function M.render(width)
	return string.rep("─", math.max(8, width or 8))
end

return M
