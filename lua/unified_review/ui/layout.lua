local diff_view = require("unified_review.ui.diff_view")

local M = {}

function M.open(session)
	diff_view.render(session)
end

return M
