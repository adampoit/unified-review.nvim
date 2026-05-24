local jobs = require("unified_review.util.jobs")

local M = {}

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function split_lines(value)
	local lines = {}
	for line in ((value or "") .. "\n"):gmatch("([^\n]*)\n") do
		if line ~= "" then
			table.insert(lines, line)
		end
	end
	return lines
end

local function run_git(args, opts)
	opts = opts or {}
	local result = jobs.run_sync("git", args, { cwd = opts.cwd, timeout = opts.timeout })
	if not result.ok then
		result.message = trim(result.stderr) ~= "" and trim(result.stderr) or "git command failed"
	end
	return result
end

M._run_git = run_git

local function absolute_path(path, cwd)
	path = trim(path)
	if path == "" then
		return path
	end
	local result = path
	if not (path:match("^/") or path:match("^%a:[/\\]")) then
		local base = vim.fn.fnamemodify(cwd or vim.fn.getcwd(), ":p"):gsub("[/\\]$", "")
		result = base .. "/" .. path
	end
	if vim.fs and vim.fs.normalize then
		result = vim.fs.normalize(result)
	end
	return result:gsub("[/\\]$", "")
end

local function is_working_head(head, range_kind)
	return head == "WORKING"
		or head == "working"
		or range_kind == "working_tree"
		or range_kind == "working_tree_three_dot"
end

local function normalize_working_range_kind(range_kind)
	if range_kind == "two_dot" or range_kind == "working_tree" then
		return "working_tree"
	end
	return "working_tree_three_dot"
end

function M.repo_root(cwd)
	local result = run_git({ "rev-parse", "--show-toplevel" }, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	return trim(result.stdout), result
end

function M.is_repo(cwd)
	return M.repo_root(cwd) ~= nil
end

function M.git_dir(cwd)
	local result = run_git({ "rev-parse", "--git-dir" }, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	return absolute_path(result.stdout, cwd), result
end

function M.resolve_ref(ref, cwd)
	local result = run_git({ "rev-parse", "--verify", ref .. "^{commit}" }, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	return trim(result.stdout), result
end

function M.ref_exists(ref, cwd)
	return M.resolve_ref(ref, cwd) ~= nil
end

function M.infer_default_branch(cwd, preferred)
	local root = M.repo_root(cwd)
	if not root then
		return preferred or "origin/main"
	end

	if preferred and M.ref_exists(preferred, root) then
		return preferred
	end

	local remote_head = run_git({ "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }, { cwd = root })
	if remote_head.ok then
		local ref = trim(remote_head.stdout)
		if ref ~= "" and M.ref_exists(ref, root) then
			return ref
		end
	end

	local upstream = run_git({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" }, { cwd = root })
	if upstream.ok then
		local ref = trim(upstream.stdout)
		if ref ~= "" and M.ref_exists(ref, root) then
			return ref
		end
	end

	for _, ref in ipairs({ "origin/main", "origin/master", "main", "master" }) do
		if M.ref_exists(ref, root) then
			return ref
		end
	end

	return preferred or "origin/main"
end

function M.merge_base(base, head, cwd)
	local result = run_git({ "merge-base", base, head }, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	return trim(result.stdout), result
end

function M.current_branch(cwd)
	local result = run_git({ "symbolic-ref", "--quiet", "--short", "HEAD" }, { cwd = cwd })
	if result.ok then
		return trim(result.stdout), nil
	end
	local detached = run_git({ "rev-parse", "--short", "HEAD" }, { cwd = cwd })
	if detached.ok then
		return trim(detached.stdout), nil
	end
	return nil, result
end

function M.has_working_changes(cwd)
	local result = run_git({ "diff", "--quiet", "HEAD", "--" }, { cwd = cwd })
	if result.code == 0 then
		return false, nil
	end
	if result.code == 1 then
		return true, nil
	end
	return nil, result
end

function M.resolve_target(target, cwd)
	target = target or {}
	local base = target.base or target.base_ref or "origin/main"
	local head = target.head or target.head_ref or "HEAD"
	local range_kind = target.range_kind or "three_dot"
	local working = is_working_head(head, range_kind)
	if working then
		range_kind = normalize_working_range_kind(range_kind)
	end

	local root, root_result = M.repo_root(cwd)
	local worktree_root = root
	local git_dir
	if not root then
		if working then
			return nil, root_result
		end
		git_dir = M.git_dir(cwd)
		if not git_dir then
			return nil, root_result
		end
		root = git_dir
	else
		git_dir = M.git_dir(root)
	end

	local base_oid, base_result
	if working and range_kind == "working_tree_three_dot" then
		base_oid, base_result = M.merge_base(base, "HEAD", root)
	elseif range_kind == "three_dot" then
		base_oid, base_result = M.merge_base(base, head, root)
	else
		base_oid, base_result = M.resolve_ref(base, root)
	end
	if not base_oid then
		return nil, base_result
	end

	local head_oid, head_result
	if working then
		head = "WORKING"
		head_oid = "WORKING"
	else
		head_oid, head_result = M.resolve_ref(head, root)
		if not head_oid then
			return nil, head_result
		end
	end

	return {
		kind = "local_git",
		root = root,
		worktree_root = worktree_root,
		git_dir = git_dir,
		base = base,
		head = head,
		range_kind = range_kind,
		base_oid = base_oid,
		head_oid = head_oid,
	},
		nil
end

function M.parse_range(args)
	args = args or {}
	if #args == 1 then
		local base, head = args[1]:match("^(.-)%.%.%.(.*)$")
		if base and head then
			return base, head ~= "" and head or "HEAD", "three_dot"
		end
		base, head = args[1]:match("^(.-)%.%.(.*)$")
		if base and head then
			return base, head ~= "" and head or "HEAD", "two_dot"
		end
	end
	return args[1], args[2], "three_dot"
end

function M.range_expr(base, head, range_kind)
	if is_working_head(head, range_kind) then
		return base
	end
	if range_kind == "two_dot" then
		return base .. ".." .. head
	end
	return base .. "..." .. head
end

local function diff_args(base, head, range_kind, extra)
	local args = { "diff" }
	vim.list_extend(args, extra or {})
	if is_working_head(head, range_kind) then
		table.insert(args, base or "HEAD")
	else
		table.insert(args, M.range_expr(base, head, range_kind))
	end
	return args
end

function M.patch(base, head, cwd, range_kind)
	return run_git(diff_args(base, head, range_kind, { "--binary", "--find-renames" }), { cwd = cwd })
end

function M.name_status(base, head, cwd, range_kind)
	return run_git(diff_args(base, head, range_kind, { "--name-status", "--find-renames" }), { cwd = cwd })
end

function M.shortstat(base, head, cwd, range_kind)
	local result = run_git(diff_args(base, head, range_kind, { "--shortstat" }), { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	return trim(result.stdout), nil
end

function M.commit_log_summary(base, head, cwd, range_kind, opts)
	opts = opts or {}
	local log_head = head
	if is_working_head(head, range_kind) then
		log_head = "HEAD"
	end
	local log_base = base
	if range_kind == "three_dot" or range_kind == "working_tree_three_dot" then
		local mb = M.merge_base(base, log_head, cwd)
		if mb then
			log_base = mb
		end
	end
	local result = run_git({
		"log",
		"--oneline",
		"--no-decorate",
		"-n",
		tostring(opts.commit_limit or 3),
		log_base .. ".." .. log_head,
	}, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	local lines = split_lines(result.stdout)
	local count_result = run_git({
		"rev-list",
		"--count",
		log_base .. ".." .. log_head,
	}, { cwd = cwd })
	local count = count_result.ok and trim(count_result.stdout) or "?"
	return {
		count = tonumber(count) or 0,
		lines = lines,
	}, nil
end

function M.diff_summary(base, head, cwd, range_kind, opts)
	opts = opts or {}
	local lines = {}
	local stat = M.shortstat(base, head, cwd, range_kind)
	if stat and stat ~= "" then
		table.insert(lines, stat)
	else
		table.insert(lines, "No file changes detected")
	end
	local status_result = M.name_status(base, head, cwd, range_kind)
	if status_result.ok then
		local file_lines = split_lines(status_result.stdout)
		local limit = opts.file_limit or 6
		for index, line in ipairs(file_lines) do
			if index > limit then
				table.insert(lines, string.format("… (%d more files)", #file_lines - limit))
				break
			end
			table.insert(lines, line)
		end
	end
	local log = M.commit_log_summary(base, head, cwd, range_kind, opts)
	if log and log.lines and #log.lines > 0 then
		table.insert(lines, string.format("─ %s commit%s in range ─", log.count, log.count == 1 and "" or "s"))
		for _, line in ipairs(log.lines) do
			table.insert(lines, "  " .. line)
		end
	end
	return lines
end

function M.recent_commits(cwd, limit)
	limit = limit or 30
	local result = run_git({
		"log",
		"--date=short",
		"--pretty=format:%H%x09%h%x09%D%x09%s",
		"-n",
		tostring(limit),
	}, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	local commits = {}
	for _, line in ipairs(split_lines(result.stdout)) do
		local oid, short, refs, subject = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
		if oid and oid ~= "" then
			table.insert(commits, {
				provider = "git",
				oid = oid,
				id = oid,
				short_id = short,
				refs = refs ~= "" and refs or nil,
				description = subject or "",
			})
		end
	end
	return commits, nil
end

return M
