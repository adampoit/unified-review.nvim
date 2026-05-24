local M = {}

local active_session

function M.get_active()
	return active_session
end

function M.set_active(session)
	active_session = session
	return active_session
end

function M.clear_active()
	active_session = nil
end

return M
