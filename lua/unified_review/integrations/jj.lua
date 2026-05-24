local git = require("unified_review.integrations.git")
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

local function run_jj(args, opts)
	opts = opts or {}
	local result = jobs.run_sync("jj", args, { cwd = opts.cwd, timeout = opts.timeout })
	if not result.ok then
		result.message = trim(result.stderr) ~= "" and trim(result.stderr) or "jj command failed"
	end
	return result
end

M._run_jj = run_jj

function M.available()
	return vim.fn.executable("jj") == 1
end

function M.workspace_root(cwd)
	local result = run_jj({ "workspace", "root" }, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	return trim(result.stdout), nil
end

function M.is_workspace(cwd)
	return M.workspace_root(cwd) ~= nil
end

function M.git_root(cwd)
	local result = run_jj({ "git", "root" }, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	return trim(result.stdout), nil
end

function M.resolve_revset(revset, cwd)
	local result = run_jj(
		{ "log", "--no-graph", "-r", revset, "--limit", "1", "-T", 'commit_id ++ "\\n"' },
		{ cwd = cwd }
	)
	if not result.ok then
		return nil, result
	end
	local oid = trim(result.stdout)
	if oid == "" then
		return nil, { message = "jj revset resolved to no commits: " .. tostring(revset) }
	end
	return oid, nil
end

function M.revset_exists(revset, cwd)
	return M.resolve_revset(revset, cwd) ~= nil
end

function M.normalize_remote_alias(revset, cwd)
	if not revset or revset == "" then
		return revset
	end
	local name = revset:match("^origin/(.+)$")
	if name then
		local bookmark = name .. "@origin"
		if not cwd or M.revset_exists(bookmark, cwd) then
			return bookmark
		end
	end
	return revset
end

local function change_summary(revset, cwd)
	local result = run_jj({
		"log",
		"--no-graph",
		"-r",
		revset,
		"--limit",
		"1",
		"-T",
		'commit_id ++ "\\t" ++ commit_id.short(12) ++ "\\t" ++ description.first_line() ++ "\\n"',
	}, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	local commit_id, short_id, description = trim(result.stdout):match("^([^\t]*)\t([^\t]*)\t(.*)$")
	if not commit_id or commit_id == "" then
		return nil, { message = "jj revset resolved to no commits: " .. tostring(revset) }
	end
	return {
		revset = revset,
		commit_id = commit_id,
		short_id = short_id,
		description = description or "",
	},
		nil
end

function M.current_change(cwd)
	local commit_id = M.resolve_revset("@", cwd)
	local parent_id = M.resolve_revset("@-", cwd)
	local current = change_summary("@", cwd) or {}
	return {
		commit_id = commit_id,
		parent_id = parent_id,
		description = current.description or "",
	}
end

function M.has_effective_diff(base, head, cwd)
	local result = run_jj({ "diff", "--from", base, "--to", head, "--summary" }, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	return trim(result.stdout) ~= "", nil
end

function M.previous_mutable_change(cwd, opts)
	opts = opts or {}
	local limit = opts.limit or 20
	local result = run_jj({
		"log",
		"--no-graph",
		"-r",
		"ancestors(@-, " .. tostring(limit) .. ") & mutable() & ~root()",
		"-T",
		'commit_id ++ "\\t" ++ commit_id.short(12) ++ "\\t" ++ description.first_line() ++ "\\n"',
	}, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	for _, line in ipairs(split_lines(result.stdout)) do
		local commit_id, short_id, description = line:match("^([^\t]*)\t([^\t]*)\t(.*)$")
		if commit_id and commit_id ~= "" then
			local parent_revset = commit_id .. "-"
			local has_diff = M.has_effective_diff(parent_revset, commit_id, cwd)
			if has_diff then
				return {
					revset = commit_id,
					commit_id = commit_id,
					short_id = short_id,
					description = description or "",
				},
					nil
			end
		end
	end
	return nil, { message = "No previous mutable jj change with a diff was found" }
end

local function parse_local_bookmarks(value)
	local bookmarks = {}
	for token in trim(value):gmatch("%S+") do
		token = token:gsub("%*$", "")
		if token ~= "" and not token:find("@", 1, true) then
			table.insert(bookmarks, token)
		end
	end
	return bookmarks
end

function M.current_bookmarks(cwd)
	local result = run_jj({ "log", "--no-graph", "-r", "@", "--limit", "1", "-T", 'bookmarks ++ "\\n"' }, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	return parse_local_bookmarks(result.stdout), nil
end

function M.closest_bookmarks(cwd)
	local result = run_jj(
		{ "log", "--no-graph", "-r", "heads(::@ & bookmarks())", "-T", 'bookmarks ++ "\\n"' },
		{ cwd = cwd }
	)
	if not result.ok then
		return nil, result
	end
	return parse_local_bookmarks(result.stdout), nil
end

function M.resolve_target(target, cwd)
	target = target or {}
	local root = target.root or target.cwd or cwd
	if not root or root == "" then
		local discovered_root, root_err = M.workspace_root(cwd)
		if not discovered_root then
			return nil, root_err
		end
		root = discovered_root
	end

	local base_revset = M.normalize_remote_alias(target.base_revset or target.base or "@-", root)
	local head_revset = M.normalize_remote_alias(target.head_revset or target.head or "@", root)
	local base_oid, base_err = target.resolved_base or target.base_oid, nil
	if not base_oid then
		base_oid, base_err = M.resolve_revset(base_revset, root)
		if not base_oid then
			return nil, base_err
		end
	end
	local head_oid, head_err = target.resolved_head or target.head_oid, nil
	if not head_oid then
		head_oid, head_err = M.resolve_revset(head_revset, root)
		if not head_oid then
			return nil, head_err
		end
	end

	local range_kind = target.range_kind or "revset"
	local patch_base = base_revset
	local patch_base_oid = base_oid
	local git_root = target.git_root or M.git_root(root)
	if range_kind == "three_dot" then
		local merge_base, merge_err = git.merge_base(base_oid, head_oid, git_root or root)
		if not merge_base then
			return nil, merge_err
		end
		patch_base = merge_base
		patch_base_oid = merge_base
	end

	local resolved = vim.tbl_extend("force", vim.deepcopy(target), {
		kind = "jj",
		root = root,
		cwd = root,
		git_root = git_root,
		base = base_revset,
		head = head_revset,
		base_revset = base_revset,
		head_revset = head_revset,
		base_oid = patch_base_oid,
		head_oid = head_oid,
		resolved_base = base_oid,
		resolved_head = head_oid,
		patch_base = patch_base,
		patch_base_oid = patch_base_oid,
		range_kind = range_kind,
	})
	return resolved, nil
end

function M.patch(target_or_base, head, cwd, range_kind)
	local target = type(target_or_base) == "table" and target_or_base
		or { base = target_or_base, head = head, range_kind = range_kind }
	local resolved, resolve_err = M.resolve_target(target, cwd)
	if not resolved then
		return {
			ok = false,
			message = resolve_err and (resolve_err.message or resolve_err.stderr) or "Unable to resolve jj target",
		}
	end
	return run_jj(
		{ "diff", "--from", resolved.patch_base, "--to", resolved.head_revset, "--git" },
		{ cwd = resolved.root }
	)
end

function M.diff_summary(base, head, cwd, opts)
	opts = opts or {}
	head = head or "@"
	local patch_base = base
	if opts.range_kind == "three_dot" then
		local resolved = M.resolve_target({ base = base, head = head, range_kind = opts.range_kind }, cwd)
		if resolved then
			patch_base = resolved.patch_base
		end
	end
	local result = run_jj({ "diff", "--from", patch_base, "--to", head, "--summary" }, { cwd = cwd })
	if not result.ok then
		return { result.message or "Unable to summarize jj diff" }
	end
	local lines = split_lines(result.stdout)
	local output = {}
	local limit = opts.file_limit or 8
	for index, line in ipairs(lines) do
		if index > limit then
			table.insert(output, string.format("… (%d more files)", #lines - limit))
			break
		end
		table.insert(output, line)
	end
	if #output == 0 then
		table.insert(output, "No file changes detected")
	end
	local log_result = run_jj({
		"log",
		"--no-graph",
		"-r",
		base .. ".." .. head,
		"-T",
		'commit_id.short(12) ++ " " ++ description.first_line() ++ "\\n"',
		"-n",
		tostring((opts.commit_limit or 3) + 1),
	}, { cwd = cwd })
	if log_result.ok then
		local commits = split_lines(log_result.stdout)
		local commit_limit = opts.commit_limit or 3
		local has_more = #commits > commit_limit
		if has_more then
			commits = vim.list_slice(commits, 1, commit_limit)
		end
		if #commits > 0 then
			local header = has_more and string.format("─ %d+ commits ─", commit_limit)
				or string.format("─ %d commit%s ─", #commits, #commits == 1 and "" or "s")
			table.insert(output, header)
			for _, line in ipairs(commits) do
				table.insert(output, "  " .. line)
			end
		end
	end
	return output
end

function M.recent_commits(cwd, limit)
	limit = limit or 30
	local result = run_jj({
		"log",
		"--no-graph",
		"-r",
		"ancestors(@, " .. tostring(limit) .. ")",
		"-T",
		'commit_id ++ "\\t" ++ commit_id.short(12) ++ "\\t" ++ change_id.short(12) ++ "\\t" ++ bookmarks ++ "\\t" ++ description.first_line() ++ "\\n"',
	}, { cwd = cwd })
	if not result.ok then
		return nil, result
	end
	local commits = {}
	for _, line in ipairs(split_lines(result.stdout)) do
		local oid, short, change_id, bookmarks, description =
			line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
		if oid and oid ~= "" then
			table.insert(commits, {
				provider = "jj",
				oid = oid,
				id = oid,
				short_id = short,
				change_id = change_id,
				refs = bookmarks ~= "" and bookmarks or nil,
				description = description or "",
			})
		end
	end
	return commits, nil
end

return M
