local jobs = require("unified_review.util.jobs")

local M = {}

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function run_gh(args, opts)
	opts = opts or {}
	local command = opts.command or "gh"
	local result = jobs.run_sync(command, args, { cwd = opts.cwd, timeout = opts.timeout, stdin = opts.stdin })
	if not result.ok then
		result.message = trim(result.stderr) ~= "" and trim(result.stderr) or "gh command failed"
	end
	return result
end

M._run_gh = run_gh

function M.available(command)
	return vim.fn.executable(command or "gh") == 1
end

local function decode_json(result)
	if not result.ok or trim(result.stdout) == "" then
		return nil, result
	end
	local ok, decoded = pcall(vim.json.decode, result.stdout)
	if not ok then
		return nil, { message = "failed to parse gh JSON: " .. tostring(decoded) }
	end
	return decoded, nil
end

local function encode_json(value)
	local ok, encoded = pcall(vim.json.encode, value)
	if not ok then
		return nil, { message = "failed to encode gh JSON: " .. tostring(encoded) }
	end
	return encoded, nil
end

function M.check_auth(cwd, opts)
	opts = opts or {}
	if not M.available(opts.command) then
		return nil, { message = "gh executable not found" }
	end
	local result = run_gh({ "auth", "status", "--json", "hosts" }, {
		cwd = cwd,
		command = opts.command,
		timeout = opts.timeout,
	})
	local decoded, err = decode_json(result)
	if not decoded then
		return nil, err
	end
	return decoded, nil
end

function M.current_pr(cwd, opts)
	opts = opts or {}
	local result = run_gh({
		"pr",
		"view",
		"--json",
		"number,url,baseRefName,headRefName,title,isDraft",
	}, { cwd = cwd, command = opts.command, timeout = opts.timeout })
	return decode_json(result)
end

function M.pr_for_head(cwd, head, opts)
	opts = opts or {}
	if not head or head == "" then
		return nil, { message = "head branch is required" }
	end
	local result = run_gh({
		"pr",
		"list",
		"--head",
		head,
		"--json",
		"number,url,baseRefName,headRefName,title,isDraft",
		"--limit",
		"1",
	}, { cwd = cwd, command = opts.command, timeout = opts.timeout })
	local list, err = decode_json(result)
	if not list then
		return nil, err
	end
	return list[1], nil
end

function M.list_open_prs(cwd, opts)
	opts = opts or {}
	if not M.available(opts.command) then
		return nil, { message = "gh executable not found" }
	end
	local result = run_gh({
		"pr",
		"list",
		"--state",
		"open",
		"--json",
		"number,url,baseRefName,headRefName,title,isDraft,author",
		"--limit",
		tostring(opts.limit or 50),
	}, { cwd = cwd, command = opts.command, timeout = opts.timeout })
	local list, err = decode_json(result)
	if not list then
		return nil, err
	end
	return list, nil
end

local function has_pr_identity(pr)
	return pr and (pr.number ~= nil or pr.url ~= nil or pr.baseRefName ~= nil)
end

function M.resolve_pr_from_branch_context(cwd, opts)
	opts = opts or {}
	if not M.available(opts.command) then
		return nil, { message = "gh executable not found" }
	end
	local pr, err = M.current_pr(cwd, opts)
	if has_pr_identity(pr) then
		return pr, nil
	end

	local head = opts.head
	if not head or head == "" then
		local ok_git, git = pcall(require, "unified_review.integrations.git")
		if ok_git then
			head = git.current_branch(cwd)
		end
	end
	if head and head ~= "" then
		pr, err = M.pr_for_head(cwd, head, opts)
		if has_pr_identity(pr) then
			return pr, nil
		end
		return nil, { message = "No GitHub PR found for current branch: " .. head, cause = err }
	end
	return nil, err or { message = "No GitHub PR found for the current branch context" }
end

function M.discover_pr_base(cwd, opts)
	opts = opts or {}
	local pr, err = M.resolve_pr_from_branch_context(cwd, opts)
	if not has_pr_identity(pr) then
		return nil, err
	end
	local pr_data = pr or {}
	local base_ref = pr_data.baseRefName and pr_data.baseRefName ~= "" and ("origin/" .. pr_data.baseRefName) or nil
	return {
		number = pr_data.number,
		url = pr_data.url,
		title = pr_data.title,
		is_draft = pr_data.isDraft,
		base_ref = base_ref,
		base_name = pr_data.baseRefName,
		head_name = pr_data.headRefName,
	},
		nil
end

local function parse_pr_url(value)
	if type(value) ~= "string" then
		return nil
	end
	local host, owner, repo, number = value:match("^https?://([^/]+)/([^/]+)/([^/]+)/pull/(%d+)")
	if not owner then
		return nil
	end
	return {
		host = host,
		owner = owner,
		repo = repo:gsub("%.git$", ""),
		number = tonumber(number),
		url = value,
	}
end

function M.parse_pr_ref(value)
	if type(value) == "number" then
		return { number = value }
	end
	value = trim(tostring(value or ""))
	if value == "" then
		return nil, { message = "PR number or URL is required" }
	end
	local parsed = parse_pr_url(value)
	if parsed then
		return parsed, nil
	end
	local number = tonumber(value:match("#?(%d+)$"))
	if number then
		return { number = number }, nil
	end
	return nil, { message = "Invalid PR reference: " .. value }
end

function M.repo_view(cwd, opts)
	opts = opts or {}
	local result = run_gh({ "repo", "view", "--json", "owner,name,url" }, {
		cwd = cwd,
		command = opts.command,
		timeout = opts.timeout,
	})
	local repo, err = decode_json(result)
	if not repo then
		return nil, err
	end
	return {
		owner = repo.owner and (repo.owner.login or repo.owner.name) or repo.owner,
		name = repo.name,
		url = repo.url,
	},
		nil
end

local pr_json_fields = table.concat({
	"id",
	"number",
	"url",
	"title",
	"body",
	"state",
	"isDraft",
	"baseRefName",
	"baseRefOid",
	"headRefName",
	"headRefOid",
	"headRepository",
	"headRepositoryOwner",
	"author",
	"additions",
	"deletions",
	"changedFiles",
}, ",")

local function normalize_pr(pr, ref, repo)
	pr = pr or {}
	repo = repo or {}
	local url_parts = parse_pr_url(pr.url or (ref and ref.url) or "") or {}
	local owner = url_parts.owner or repo.owner
	local repo_name = url_parts.repo or repo.name
	return {
		id = pr.id,
		number = tonumber(pr.number or (ref and ref.number)),
		url = pr.url or (ref and ref.url),
		title = pr.title,
		body = pr.body,
		state = pr.state,
		is_draft = pr.isDraft,
		base_ref = pr.baseRefName,
		base_ref_oid = pr.baseRefOid,
		head_ref = pr.headRefName,
		head_ref_oid = pr.headRefOid,
		owner = owner,
		repo = repo_name,
		author = pr.author and pr.author.login,
		additions = pr.additions,
		deletions = pr.deletions,
		changed_files = pr.changedFiles,
		metadata = pr,
	}
end

function M.pr_view(cwd, pr_ref, opts)
	opts = opts or {}
	local ref, parse_err = M.parse_pr_ref(pr_ref)
	if not ref then
		return nil, parse_err
	end
	local view_arg = ref.url or tostring(ref.number)
	local result = run_gh({ "pr", "view", view_arg, "--json", pr_json_fields }, {
		cwd = cwd,
		command = opts.command,
		timeout = opts.timeout,
	})
	local pr, err = decode_json(result)
	if not pr then
		return nil, err
	end
	local repo = ref.owner and { owner = ref.owner, name = ref.repo } or nil
	if not repo then
		repo = M.repo_view(cwd, opts) or {}
	end
	return normalize_pr(pr, ref, repo), nil
end

function M.pr_diff(cwd, pr_ref, opts)
	opts = opts or {}
	local ref, parse_err = M.parse_pr_ref(pr_ref)
	if not ref then
		return nil, parse_err
	end
	local diff_arg = ref.url or tostring(ref.number)
	local result = run_gh({ "pr", "diff", diff_arg, "--patch" }, {
		cwd = cwd,
		command = opts.command,
		timeout = opts.timeout,
	})
	if not result.ok then
		return nil, result
	end
	return result.stdout or "", nil
end

function M.graphql(query, variables, opts)
	opts = opts or {}
	local body, encode_err = encode_json({ query = query, variables = variables or {} })
	if not body then
		return nil, encode_err
	end
	local result = run_gh({ "api", "graphql", "--input", "-" }, {
		cwd = opts.cwd,
		command = opts.command,
		timeout = opts.timeout,
		stdin = body,
	})
	return decode_json(result)
end

function M.api(method, path, body, opts)
	opts = opts or {}
	local args = { "api", path, "--method", method or "GET" }
	local stdin
	if body ~= nil then
		local encoded, encode_err = encode_json(body)
		if not encoded then
			return nil, encode_err
		end
		stdin = encoded
		table.insert(args, "--input")
		table.insert(args, "-")
	end
	local result = run_gh(args, {
		cwd = opts.cwd,
		command = opts.command,
		timeout = opts.timeout,
		stdin = stdin,
	})
	return decode_json(result)
end

return M
