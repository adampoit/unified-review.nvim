local config = require("unified_review.config")
local gh = require("unified_review.integrations.gh")
local git = require("unified_review.integrations.git")
local git_provider = require("unified_review.providers.diff.git_local")
local parser = require("unified_review.util.patch_parse")
local review_target = require("unified_review.domain.review_target")
local jobs = require("unified_review.util.jobs")

local M = {}

local function annotate_github_positions(files)
	for _, file in ipairs(files or {}) do
		local position = 0
		file.metadata = file.metadata or {}
		file.metadata.github = file.metadata.github or {}
		for _, hunk in ipairs(file.hunks or {}) do
			position = position + 1
			hunk.metadata = hunk.metadata or {}
			hunk.metadata.github_position = position
			for _, line in ipairs(hunk.lines or {}) do
				position = position + 1
				line.metadata = line.metadata or {}
				line.metadata.github = {
					position = position,
					path = file.path,
					old_line = line.old_line,
					new_line = line.new_line,
					side = line.kind == "deleted" and "LEFT" or "RIGHT",
				}
			end
		end
	end
	return files
end

local function is_local_worktree_target(target)
	return target and (target.render_strategy == "local_worktree" or target.local_worktree == true)
end

local function session_id(target)
	local prefix = is_local_worktree_target(target) and "github-local" or "github"
	return table.concat({ prefix, target.owner or "", target.repo or "", tostring(target.number or "") }, ":")
end

local function ensure_parent(path)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
end

local function snapshot_lines(file)
	local base = {}
	local head = {}
	local max_base = 0
	local max_head = 0
	for _, hunk in ipairs(file.hunks or {}) do
		for _, line in ipairs(hunk.lines or {}) do
			if line.kind == "context" then
				if line.old_line then
					base[line.old_line] = line.text
					max_base = math.max(max_base, line.old_line)
				end
				if line.new_line then
					head[line.new_line] = line.text
					max_head = math.max(max_head, line.new_line)
				end
			elseif line.kind == "deleted" then
				base[line.old_line] = line.text
				max_base = math.max(max_base, line.old_line or 0)
			elseif line.kind == "added" then
				head[line.new_line] = line.text
				max_head = math.max(max_head, line.new_line or 0)
			end
		end
	end
	local function compact(lines, max_line)
		local result = {}
		for index = 1, max_line do
			table.insert(result, lines[index] or "")
		end
		return result
	end
	return compact(base, max_base), compact(head, max_head)
end

local function write_snapshot(root, file, side)
	local path = root .. "/" .. (side == "base" and (file.old_path or file.path) or file.path)
	if (side == "base" and file.status == "added") or (side == "head" and file.status == "deleted") then
		vim.fn.delete(path)
		return
	end
	local base_lines, head_lines = snapshot_lines(file)
	ensure_parent(path)
	vim.fn.writefile(side == "base" and base_lines or head_lines, path)
end

local function run_git(root, args, opts)
	opts = opts or {}
	return jobs.run_sync("git", vim.list_extend({ "-C", root }, args), { timeout = opts.timeout or 10000 })
end

local function run_git_async(root, args, opts, callback)
	opts = opts or {}
	return jobs.run_async("git", vim.list_extend({ "-C", root }, args), { timeout = opts.timeout or 10000 }, callback)
end

local function local_remote_url(cwd)
	if not cwd or cwd == "" then
		return nil
	end
	local inside = jobs.run_sync("git", { "-C", cwd, "rev-parse", "--is-inside-work-tree" }, { timeout = 10000 })
	if not inside.ok then
		return nil
	end
	local remote = jobs.run_sync("git", { "-C", cwd, "config", "--get", "remote.origin.url" }, { timeout = 10000 })
	if not remote.ok then
		return nil
	end
	return (remote.stdout or ""):gsub("%s+$", "")
end

local function materialize_from_remote(pr, cwd)
	if not pr or not pr.number or not pr.base_ref then
		return nil
	end
	local remote = local_remote_url(cwd)
	if not remote or remote == "" then
		return nil
	end
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local function ok(args, opts)
		local result = run_git(root, args, opts)
		return result.ok and result or nil
	end
	if not jobs.run_sync("git", { "init", root }, { timeout = 10000 }).ok then
		return nil
	end
	if not ok({ "remote", "add", "origin", remote }) then
		return nil
	end
	local base_ref = "+refs/heads/" .. pr.base_ref .. ":refs/remotes/origin/__unified_review_base"
	local head_ref = "+refs/pull/" .. tostring(pr.number) .. "/head:refs/remotes/origin/__unified_review_pr"
	if not ok({ "fetch", "--no-tags", "--filter=blob:none", "origin", base_ref, head_ref }, { timeout = 60000 }) then
		return nil
	end
	local base =
		ok({ "merge-base", "refs/remotes/origin/__unified_review_base", "refs/remotes/origin/__unified_review_pr" })
	if not base then
		return nil
	end
	if not ok({ "checkout", "--detach", "refs/remotes/origin/__unified_review_pr" }, { timeout = 60000 }) then
		return nil
	end
	return root, (base.stdout or ""):gsub("%s+$", "")
end

local function materialize_from_remote_async(pr, cwd, callback)
	if not pr or not pr.number or not pr.base_ref then
		vim.schedule(function()
			callback(nil)
		end)
		return nil
	end
	local remote = local_remote_url(cwd)
	if not remote or remote == "" then
		vim.schedule(function()
			callback(nil)
		end)
		return nil
	end
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local base_ref = "+refs/heads/" .. pr.base_ref .. ":refs/remotes/origin/__unified_review_base"
	local head_ref = "+refs/pull/" .. tostring(pr.number) .. "/head:refs/remotes/origin/__unified_review_pr"

	jobs.run_async("git", { "init", root }, { timeout = 10000 }, function(init)
		if not init.ok then
			callback(nil)
			return
		end
		run_git_async(root, { "remote", "add", "origin", remote }, nil, function(remote_add)
			if not remote_add.ok then
				callback(nil)
				return
			end
			run_git_async(
				root,
				{ "fetch", "--no-tags", "--filter=blob:none", "origin", base_ref, head_ref },
				{ timeout = 60000 },
				function(fetch)
					if not fetch.ok then
						callback(nil)
						return
					end
					run_git_async(
						root,
						{
							"merge-base",
							"refs/remotes/origin/__unified_review_base",
							"refs/remotes/origin/__unified_review_pr",
						},
						nil,
						function(base)
							if not base.ok then
								callback(nil)
								return
							end
							run_git_async(
								root,
								{ "checkout", "--detach", "refs/remotes/origin/__unified_review_pr" },
								{ timeout = 60000 },
								function(checkout)
									if not checkout.ok then
										callback(nil)
										return
									end
									callback(root, (base.stdout or ""):gsub("%s+$", ""))
								end
							)
						end
					)
				end
			)
		end)
	end)
end

local function materialize_patch(files)
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	jobs.run_sync("git", { "init", root }, { timeout = 10000 })
	run_git(root, { "config", "user.email", "unified-review@example.invalid" })
	run_git(root, { "config", "user.name", "unified-review" })
	for _, file in ipairs(files or {}) do
		write_snapshot(root, file, "base")
	end
	run_git(root, { "add", "." })
	run_git(root, { "commit", "--allow-empty", "-m", "github-pr-base" })
	local base = run_git(root, { "rev-parse", "HEAD" })
	for _, file in ipairs(files or {}) do
		write_snapshot(root, file, "head")
	end
	return root, (base.stdout or ""):gsub("%s+$", "")
end

local function local_base_ref(pr, cwd)
	if not pr then
		return nil
	end
	local candidates = {}
	if pr.base_ref and pr.base_ref ~= "" then
		table.insert(candidates, "origin/" .. pr.base_ref)
		table.insert(candidates, pr.base_ref)
	end
	if pr.base_ref_oid and pr.base_ref_oid ~= "" then
		table.insert(candidates, pr.base_ref_oid)
	end
	for _, ref in ipairs(candidates) do
		if git.ref_exists(ref, cwd) then
			return ref
		end
	end
	return candidates[1]
end

local function local_base_revset(target, pr, cwd)
	if target.local_base or target.base_revset then
		return target.local_base or target.base_revset
	end
	local ok_jj, jj = pcall(require, "unified_review.integrations.jj")
	if pr and pr.base_ref and pr.base_ref ~= "" then
		local ref = "origin/" .. pr.base_ref
		return ok_jj and jj.normalize_remote_alias(ref, cwd) or ref
	end
	return target.base or target.base_ref
end

local function local_worktree_session_error(local_err)
	return {
		message = "Unable to open the local worktree for this PR review: "
			.. (local_err and (local_err.message or local_err.stderr) or "unknown error"),
		cause = local_err,
	}
end

local function build_local_worktree_result(target, cwd, pr, remote_patch, local_session, opts)
	opts = opts or {}
	local resolved = local_session.target or {}
	local remote_files = annotate_github_positions(parser.parse(remote_patch or ""))
	local render_root = resolved.worktree_root or resolved.root
	local normalized_target = review_target.github_pr_local_worktree(vim.tbl_extend("force", target, {
		root = render_root,
		worktree_root = resolved.worktree_root,
		git_root = resolved.git_root or resolved.root,
		git_dir = resolved.git_dir,
		cwd = cwd,
		source_root = opts.source_root or render_root or cwd,
		owner = pr.owner,
		repo = pr.repo,
		number = pr.number,
		url = pr.url,
		title = pr.title,
		pull_request_id = pr.id,
		base = resolved.base,
		head = opts.head or resolved.head,
		base_ref = pr.base_ref,
		head_ref = pr.head_ref,
		base_oid = resolved.base_oid,
		head_oid = opts.head_oid or resolved.head_oid,
		render_base_oid = resolved.base_oid,
		render_head_oid = opts.head_oid or resolved.head_oid,
		metadata = vim.tbl_extend("force", target.metadata or {}, {
			github = pr,
			github_base_oid = pr.base_ref_oid,
			github_head_oid = pr.head_ref_oid,
			render_root = render_root,
			render_strategy = "local_worktree",
		}),
	}))
	return {
		id = session_id(normalized_target),
		provider = "github_pr",
		kind = "github_pr",
		target = normalized_target,
		files = local_session.files,
		raw_patch = local_session.raw_patch,
		editable = false,
		read_only = true,
		threads = {},
		metadata = {
			github = pr,
			render_strategy = "local_worktree",
			github_remote_files = remote_files,
			github_remote_patch = remote_patch,
		},
	},
		nil
end

local function build_jj_local_worktree_session(target, cwd, pr, remote_patch)
	local ok_provider, jj_provider = pcall(require, "unified_review.providers.diff.jj_local")
	if not ok_provider or type(jj_provider.open) ~= "function" then
		return nil, { message = "jj diff provider is not available" }
	end
	local jj_root = target.local_root or target.jj_root or target.workspace_root or target.root or cwd
	local base = local_base_revset(target, pr, jj_root)
	if not base then
		return nil, { message = "Unable to determine a local base for the PR worktree review" }
	end
	local local_session, local_err = jj_provider.open({
		cwd = jj_root,
		root = jj_root,
		git_root = target.git_root,
		base = base,
		head = target.local_head or target.head_revset or "@",
		range_kind = target.local_range_kind or target.range_kind or "three_dot",
	})
	if not local_session then
		return nil, local_worktree_session_error(local_err)
	end
	return build_local_worktree_result(target, cwd, pr, remote_patch, local_session, {
		source_root = jj_root,
		head = local_session.target and local_session.target.head or "@",
		head_oid = local_session.target and local_session.target.head_oid,
	})
end

local function build_git_local_worktree_session(target, cwd, pr, remote_patch)
	local base = target.local_base or target.base or target.base_ref or local_base_ref(pr, cwd)
	if not base then
		return nil, { message = "Unable to determine a local base for the PR worktree review" }
	end
	local local_session, local_err = git_provider.open({
		cwd = cwd,
		root = cwd,
		base = base,
		head = "WORKING",
		range_kind = target.local_range_kind or target.range_kind or "working_tree_three_dot",
		editable = false,
	})
	if not local_session then
		return nil, local_worktree_session_error(local_err)
	end
	return build_local_worktree_result(
		target,
		cwd,
		pr,
		remote_patch,
		local_session,
		{ head = "WORKING", head_oid = "WORKING" }
	)
end

local function build_local_worktree_session(target, cwd, pr, remote_patch)
	if target.local_provider == "jj" then
		return build_jj_local_worktree_session(target, cwd, pr, remote_patch)
	end
	return build_git_local_worktree_session(target, cwd, pr, remote_patch)
end

local function build_session(target, cwd, pr, patch, files, render_root, render_base_oid)
	local normalized_target = review_target.github_pr(vim.tbl_extend("force", target, {
		root = render_root,
		cwd = cwd,
		source_root = cwd,
		owner = pr.owner,
		repo = pr.repo,
		number = pr.number,
		url = pr.url,
		title = pr.title,
		pull_request_id = pr.id,
		base = pr.base_ref,
		head = pr.head_ref,
		base_ref = pr.base_ref,
		head_ref = pr.head_ref,
		base_oid = render_base_oid,
		head_oid = pr.head_ref_oid,
		render_base_oid = render_base_oid,
		render_head_oid = "WORKING",
		metadata = vim.tbl_extend("force", target.metadata or {}, {
			github = pr,
			github_base_oid = pr.base_ref_oid,
			github_head_oid = pr.head_ref_oid,
			render_root = render_root,
		}),
	}))
	return {
		id = session_id(normalized_target),
		provider = "github_pr",
		kind = "github_pr",
		target = normalized_target,
		files = files,
		raw_patch = patch,
		editable = false,
		read_only = true,
		threads = {},
		metadata = { github = pr },
	}
end

function M.open(target)
	target = target or {}
	local github_cfg = config.options.github or config.defaults.github
	local cwd = target.cwd or target.root or vim.loop.cwd()
	local pr_ref = target.url or target.number or target.pr or target.ref
	if not gh.available(github_cfg.transport_command) then
		return nil, { message = "gh executable not found" }
	end
	if not pr_ref then
		local context_pr, context_err = gh.resolve_pr_from_branch_context(cwd, {
			command = github_cfg.transport_command,
			timeout = github_cfg.timeout,
		})
		if not context_pr then
			return nil, context_err
		end
		pr_ref = context_pr.url or context_pr.number
	end
	local pr, pr_err = gh.pr_view(cwd, pr_ref, {
		command = github_cfg.transport_command,
		timeout = github_cfg.timeout,
	})
	if not pr then
		return nil, pr_err
	end
	local patch, patch_err = gh.pr_diff(cwd, pr.url or pr.number or pr_ref, {
		command = github_cfg.transport_command,
		timeout = github_cfg.timeout,
	})
	if not patch then
		return nil, patch_err
	end
	if is_local_worktree_target(target) then
		return build_local_worktree_session(target, cwd, pr, patch)
	end
	local files = annotate_github_positions(parser.parse(patch))
	local render_root, render_base_oid = materialize_from_remote(pr, cwd)
	if not render_root then
		render_root, render_base_oid = materialize_patch(files)
	end
	return build_session(target, cwd, pr, patch, files, render_root, render_base_oid), nil
end

function M.open_async(target, callback)
	target = target or {}
	local github_cfg = config.options.github or config.defaults.github
	local cwd = target.cwd or target.root or vim.loop.cwd()
	local pr_ref = target.url or target.number or target.pr or target.ref
	if not gh.available(github_cfg.transport_command) then
		vim.schedule(function()
			callback(nil, { message = "gh executable not found" })
		end)
		return nil
	end
	if not pr_ref then
		vim.schedule(function()
			callback(M.open(target))
		end)
		return nil
	end
	return gh.pr_view_async(cwd, pr_ref, {
		command = github_cfg.transport_command,
		timeout = github_cfg.timeout,
	}, function(pr, pr_err)
		if not pr then
			callback(nil, pr_err)
			return
		end
		gh.pr_diff_async(cwd, pr.url or pr.number or pr_ref, {
			command = github_cfg.transport_command,
			timeout = github_cfg.timeout,
		}, function(patch, patch_err)
			if not patch then
				callback(nil, patch_err)
				return
			end
			if is_local_worktree_target(target) then
				callback(build_local_worktree_session(target, cwd, pr, patch))
				return
			end
			local files = annotate_github_positions(parser.parse(patch))
			materialize_from_remote_async(pr, cwd, function(render_root, render_base_oid)
				if not render_root then
					render_root, render_base_oid = materialize_patch(files)
				end
				callback(build_session(target, cwd, pr, patch, files, render_root, render_base_oid), nil)
			end)
		end)
	end)
end

function M.refresh(session)
	return M.open(session.target or {})
end

function M.get_file(session, path)
	for _, file in ipairs(session.files or {}) do
		if file.path == path or file.old_path == path then
			return file
		end
	end
	return nil
end

---@diagnostic disable-next-line: unused-local
function M.map_visual_range(session, path, start_row, end_row, side)
	if start_row == end_row then
		return { kind = "line", path = path, side = side, line = start_row }
	end
	return {
		kind = "range",
		path = path,
		start_side = side,
		start_line = start_row,
		side = side,
		line = end_row,
	}
end

return M
