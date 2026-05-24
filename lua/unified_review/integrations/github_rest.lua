local gh = require("unified_review.integrations.gh")

local M = {}

local function repo_path(target, suffix)
	target = target or {}
	if not target.owner or not target.repo then
		return nil, { message = "GitHub target is missing owner or repo" }
	end
	return string.format("/repos/%s/%s%s", target.owner, target.repo, suffix or ""), nil
end

function M.request(method, path, body, opts)
	return gh.api(method, path, body, opts or {})
end

function M.pull_request(target, opts)
	local path, err = repo_path(target, "/pulls/" .. tostring(target.number or ""))
	if not path then
		return nil, err
	end
	return M.request("GET", path, nil, opts)
end

function M.create_review(target, body, opts)
	local path, err = repo_path(target, "/pulls/" .. tostring(target.number or "") .. "/reviews")
	if not path then
		return nil, err
	end
	return M.request("POST", path, body or {}, opts)
end

function M.submit_review(target, review_id, event, body, opts)
	local path, err = repo_path(
		target,
		"/pulls/" .. tostring(target.number or "") .. "/reviews/" .. tostring(review_id or "") .. "/events"
	)
	if not path then
		return nil, err
	end
	return M.request("POST", path, { event = event or "COMMENT", body = body or "" }, opts)
end

return M
