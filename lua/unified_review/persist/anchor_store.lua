local M = {}

function M.set(session, key, anchor)
	session.anchors = session.anchors or {}
	session.anchors[key] = anchor
	return anchor
end

function M.get(session, key)
	return session.anchors and session.anchors[key] or nil
end

return M
