local M = {}

function M.is_draft(comment)
	return comment and comment.state == "draft"
end

function M.github_metadata(comment)
	return comment and comment.metadata and comment.metadata.github or nil
end

function M.is_remote(comment)
	return M.github_metadata(comment) ~= nil or (comment and comment.state == "remote")
end

function M.is_local_draft(comment)
	return M.is_draft(comment) and M.github_metadata(comment) == nil
end

function M.is_remote_draft(comment)
	return M.is_draft(comment) and M.github_metadata(comment) ~= nil
end

function M.draft_label(comment)
	if M.is_local_draft(comment) then
		return "local draft"
	end
	if M.is_remote_draft(comment) then
		return "remote draft"
	end
	return comment and comment.state or "remote"
end

return M
