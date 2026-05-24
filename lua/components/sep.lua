local make = require("components.component").make

local M = {}

function M.component(value, opts)
	opts = opts or {}
	return make("sep", { value = value or " · ", hl = opts.hl })
end

return M
