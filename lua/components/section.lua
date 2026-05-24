local make = require("components.component").make

local M = {}

function M.component(title, opts)
	opts = opts or {}
	return make("section", { title = tostring(title or ""), hl = opts.hl })
end

return M
