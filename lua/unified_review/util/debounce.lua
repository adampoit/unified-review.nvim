---@diagnostic disable: deprecated
local M = {}

function M.debounce(ms, fn)
	local timer

	return function(...)
		local argv = { ... }
		if timer then
			timer:stop()
			timer:close()
		end

		timer = vim.uv.new_timer()
		timer:start(ms, 0, function()
			timer:stop()
			timer:close()
			timer = nil
			vim.schedule(function()
				fn(unpack(argv))
			end)
		end)
	end
end

return M
