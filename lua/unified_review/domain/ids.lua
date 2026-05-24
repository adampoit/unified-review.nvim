local M = {}

local counters = {}

function M.new(prefix)
	counters[prefix] = (counters[prefix] or 0) + 1
	return table.concat({ prefix, tostring(os.time()), tostring(counters[prefix]) }, "-")
end

return M
