local config = require("unified_review.config")
local git = require("unified_review.integrations.git")
local review_target = require("unified_review.domain.review_target")

local M = {}

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function title_case(value)
	value = tostring(value or "")
	return value:sub(1, 1):upper() .. value:sub(2)
end

local function clone_list(value)
	local out = {}
	for _, item in ipairs(value or {}) do
		table.insert(out, item)
	end
	return out
end

local function command_error_message(err)
	return err and (err.message or err.stderr) or "unknown error"
end

local function cwd_or_default(cwd)
	return cwd or vim.fn.getcwd()
end

local function item(opts)
	opts = opts or {}
	return {
		id = opts.id or opts.label,
		kind = opts.kind or "target",
		label = opts.label or "Review target",
		description = opts.description or "",
		badge = opts.badge or "git",
		target = opts.target,
		summary_lines = clone_list(opts.summary_lines),
		warnings = clone_list(opts.warnings),
		disabled = opts.disabled == true,
	}
end

local function add_git_item(items, root, opts)
	local make_target = opts.badge == "pr" and review_target.local_pr_base or review_target.local_git
	local target = make_target({
		cwd = root,
		root = root,
		base = opts.base,
		head = opts.head,
		range_kind = opts.range_kind,
		provider_kind = opts.badge or "git",
		raw_base = opts.raw_base or opts.base,
		raw_head = opts.raw_head or opts.head,
		fallback_notes = opts.fallback_notes,
	})
	local summary_lines = opts.summary_lines
	if not summary_lines then
		local resolved = git.resolve_target(target, root)
		local summary_base = target.base
		if resolved and resolved.head_oid == "WORKING" then
			summary_base = resolved.base_oid
		end
		summary_lines = git.diff_summary(summary_base, target.head, root, target.range_kind)
	end
	table.insert(
		items,
		item({
			id = opts.id or (target.base .. "->" .. target.head),
			label = opts.label,
			description = opts.description,
			badge = opts.badge or "git",
			target = target,
			summary_lines = summary_lines,
			warnings = opts.warnings,
		})
	)
end

local function add_github_pr_item(items, root, pr, opts)
	opts = opts or {}
	if not pr or not (pr.number or pr.url) then
		return
	end
	table.insert(
		items,
		item({
			id = opts.id or "github-pr",
			label = string.format("Review GitHub PR #%s", tostring(pr.number or "?")),
			description = pr.title or "Open the pull request review without checking it out",
			badge = "pr",
			target = review_target.github_pr({
				cwd = opts.cwd or root,
				root = opts.cwd or root,
				number = pr.number,
				url = pr.url,
				title = pr.title,
				raw_head = pr.head_name,
				raw_base = pr.base_name,
			}),
			summary_lines = {
				string.format("GitHub PR: %s", pr.url or ("#" .. tostring(pr.number))),
				pr.base_name and pr.head_name and string.format("%s ← %s", pr.base_name, pr.head_name) or nil,
			},
		})
	)
end

local function discover_pr_for_git(root, head_ref)
	local ok_gh, gh = pcall(require, "unified_review.integrations.gh")
	if not ok_gh or not gh.available(config.options.github.transport_command) then
		return nil
	end
	return gh.discover_pr_base(root, { command = config.options.github.transport_command, head = head_ref })
end

local function append_meta_items(items, mode, root, opts)
	opts = opts or {}
	if opts.inferred_pr then
		add_github_pr_item(items, root, opts.inferred_pr, {
			id = opts.inferred_pr_id,
			cwd = opts.github_cwd,
		})
	end
	local ok_gh, gh = pcall(require, "unified_review.integrations.gh")
	local gh_available = ok_gh and gh.available(config.options.github.transport_command)
	table.insert(
		items,
		item({
			id = "github-pr-picker",
			kind = "github_pr_picker",
			label = "GitHub PR",
			description = "Pick from open pull requests",
			badge = "pr",
			disabled = not gh_available,
			warnings = gh_available and {} or { "gh executable not found" },
			summary_lines = { "Open a PR review without checking out the branch." },
		})
	)
	local repository_available = mode == "git" or mode == "jj" or root ~= nil
	local range_warnings = repository_available and {} or { "Open inside a Git or jj repository to use commit ranges." }
	table.insert(
		items,
		item({
			id = "commit-range",
			kind = "commit_range",
			label = "Commit range",
			description = mode == "jj" and "Pick base/head from recent jj changes"
				or "Pick base/head from recent Git commits",
			badge = "range",
			disabled = not repository_available,
			warnings = range_warnings,
		})
	)
	table.insert(
		items,
		item({
			id = "custom",
			kind = "custom",
			label = "Custom target",
			description = mode == "jj" and "Type a jj revset or range" or "Type a Git ref or range",
			badge = "custom",
			summary_lines = opts and opts.empty_message and { opts.empty_message } or nil,
		})
	)
end

local function discover_git(cwd)
	local root, root_err = git.repo_root(cwd)
	if not root then
		return nil, root_err
	end
	local items = {}
	local branch = git.current_branch(root) or "HEAD"
	local has_working = git.has_working_changes(root)
	if has_working then
		add_git_item(items, root, {
			id = "git-working",
			label = "Working tree changes",
			description = "Tracked working-tree changes against HEAD",
			badge = "git",
			base = "HEAD",
			head = "WORKING",
			range_kind = "working_tree",
		})
	end

	local added_refs = {}
	for _, ref in ipairs({ "origin/main", "origin/master" }) do
		if git.ref_exists(ref, root) and not added_refs[ref] then
			added_refs[ref] = true
			add_git_item(items, root, {
				id = "git-" .. ref,
				label = ref .. " → current code",
				description = "Only your branch's changes",
				badge = "origin",
				base = ref,
				head = "WORKING",
				range_kind = "working_tree_three_dot",
			})
			add_git_item(items, root, {
				id = "git-" .. ref .. "-two-dot",
				label = ref .. " .. current code",
				description = "Full diff between both refs",
				badge = "origin",
				base = ref,
				head = "WORKING",
				range_kind = "working_tree",
			})
		end
	end

	if git.ref_exists("HEAD~1", root) then
		add_git_item(items, root, {
			id = "git-last-commit",
			label = "Last commit",
			description = "HEAD~1 → HEAD",
			badge = "git",
			base = "HEAD~1",
			head = "HEAD",
			range_kind = "two_dot",
		})
	end

	local inferred_pr = discover_pr_for_git(root, branch)
	append_meta_items(
		items,
		"git",
		root,
		{ inferred_pr = inferred_pr, inferred_pr_id = "github-pr", github_cwd = root }
	)

	return {
		mode = "git",
		provider = "git",
		cwd = cwd,
		root = root,
		items = items,
		warnings = {},
	}, nil
end

local function add_jj_item(items, jj, root, git_root, opts)
	local base = jj.normalize_remote_alias(opts.base or opts.base_revset, root)
	local head = jj.normalize_remote_alias(opts.head or opts.head_revset or "@", root)
	local target = review_target.jj({
		root = root,
		cwd = root,
		git_root = git_root,
		base = base,
		head = head,
		base_revset = base,
		head_revset = head,
		provider_kind = opts.badge == "pr" and "pr" or "jj",
		raw_base = opts.raw_base or opts.base or opts.base_revset,
		raw_head = opts.raw_head or opts.head or opts.head_revset or "@",
		resolved_base = opts.resolved_base,
		resolved_head = opts.resolved_head,
		range_kind = opts.range_kind,
	})
	local summary_lines = opts.summary_lines
	if not summary_lines then
		if opts.range_kind == "three_dot" and git_root and git_root ~= "" then
			local ok_git, git_integration = pcall(require, "unified_review.integrations.git")
			if ok_git and type(jj.resolve_revset) == "function" then
				local base_oid = opts.resolved_base
				if not base_oid then
					local ok_b, b = pcall(jj.resolve_revset, base, root)
					base_oid = ok_b and b or nil
				end
				local head_oid = opts.resolved_head
				if not head_oid then
					local ok_h, h = pcall(jj.resolve_revset, head, root)
					head_oid = ok_h and h or nil
				end
				if base_oid and head_oid then
					local mb = git_integration.merge_base(base_oid, head_oid, git_root)
					if mb then
						summary_lines = git_integration.diff_summary(mb, head_oid, git_root, "two_dot", {
							file_limit = opts.file_limit,
							commit_limit = opts.commit_limit,
						})
					end
				end
			end
		end
		summary_lines = summary_lines or jj.diff_summary(base, head, root, { range_kind = opts.range_kind })
	end
	table.insert(
		items,
		item({
			id = opts.id or (base .. "->" .. head),
			label = opts.label,
			description = opts.description,
			badge = opts.badge or "jj",
			target = target,
			summary_lines = summary_lines,
			warnings = opts.warnings,
		})
	)
end

local function discover_pr_for_jj(jj, root, git_root)
	local ok_gh, gh = pcall(require, "unified_review.integrations.gh")
	if not ok_gh or not gh.available(config.options.github.transport_command) then
		return nil
	end
	local bookmarks = type(jj.current_bookmarks) == "function" and jj.current_bookmarks(root) or {}
	if (not bookmarks or #bookmarks == 0) and type(jj.closest_bookmarks) == "function" then
		bookmarks = jj.closest_bookmarks(root) or {}
	end
	return gh.discover_pr_base(git_root or root, {
		command = config.options.github.transport_command,
		head = bookmarks and bookmarks[1] or nil,
	})
end

local function discover_jj(cwd)
	local ok_jj, jj = pcall(require, "unified_review.integrations.jj")
	if not ok_jj then
		return nil, { message = "jj integration failed to load" }
	end
	local root, root_err = jj.workspace_root(cwd)
	if not root then
		return nil, root_err
	end
	local git_root = jj.git_root(root)
	local items = {}
	local current = jj.current_change(root)
	add_jj_item(items, jj, root, git_root, {
		id = "jj-current",
		label = "Current jj change",
		description = current.description ~= "" and current.description or "@- → @",
		badge = "jj",
		base = "@-",
		head = "@",
		resolved_base = current.parent_id,
		resolved_head = current.commit_id,
	})
	if jj.revset_exists(config.options.jj.base_revset or "trunk()", root) then
		local base = config.options.jj.base_revset or "trunk()"
		add_jj_item(items, jj, root, git_root, {
			id = "jj-trunk",
			label = title_case(base) .. " → @",
			description = "Configured jj baseline compared with the current change",
			badge = "jj",
			base = base,
			head = "@",
		})
	end
	for _, bookmark in ipairs({ "main@origin", "master@origin" }) do
		if jj.revset_exists(bookmark, root) then
			add_jj_item(items, jj, root, git_root, {
				id = "jj-" .. bookmark,
				label = bookmark .. " → @",
				description = "Full diff between both refs",
				badge = "origin",
				base = bookmark,
				head = "@",
				raw_base = "origin/" .. bookmark:gsub("@origin$", ""),
				range_kind = "two_dot",
			})
			add_jj_item(items, jj, root, git_root, {
				id = "jj-" .. bookmark .. "-three-dot",
				label = bookmark .. " ... @",
				description = "Only your branch's changes",
				badge = "origin",
				base = bookmark,
				head = "@",
				raw_base = "origin/" .. bookmark:gsub("@origin$", ""),
				range_kind = "three_dot",
			})
		end
	end
	local inferred_pr = discover_pr_for_jj(jj, root, git_root)
	append_meta_items(
		items,
		"jj",
		root,
		{ inferred_pr = inferred_pr, inferred_pr_id = "jj-github-pr", github_cwd = git_root or root }
	)
	return {
		mode = "jj",
		provider = "jj",
		cwd = cwd,
		root = root,
		git_root = git_root,
		items = items,
		warnings = {},
	},
		nil
end

local function jj_current_target(cwd, opts)
	opts = opts or {}
	local ok_jj, jj = pcall(require, "unified_review.integrations.jj")
	if not ok_jj then
		return nil, { message = "jj integration failed to load" }
	end
	local root, root_err = jj.workspace_root(cwd)
	if not root then
		return nil, root_err
	end
	local git_root = jj.git_root(root)
	local base = opts.base_revset or config.options.jj.base_revset or "trunk()"
	base = jj.normalize_remote_alias(base, root)
	local resolved_base, base_err = jj.resolve_revset(base, root)
	if not resolved_base then
		return nil,
			{
				message = "Unable to resolve jj current base `" .. tostring(base) .. "`: " .. command_error_message(
					base_err
				),
			}
	end

	local current = jj.current_change(root)
	local head = "@"
	local resolved_head = current.commit_id
	local warnings = {}
	local fallback_notes
	local has_current_diff, diff_err = jj.has_effective_diff("@-", "@", root)
	if has_current_diff == false then
		local fallback = jj.previous_mutable_change(root)
		if fallback then
			head = fallback.revset or fallback.commit_id
			resolved_head = fallback.commit_id
			fallback_notes = {
				string.format(
					"Current jj working-copy commit has no diff; reviewing previous mutable change %s instead.",
					fallback.short_id or fallback.commit_id
				),
			}
			warnings = clone_list(fallback_notes)
		else
			warnings = { "Current jj working-copy commit has no diff and no previous mutable change was found." }
		end
	elseif has_current_diff == nil and diff_err then
		warnings = { "Unable to check current jj diff: " .. command_error_message(diff_err) }
	end

	local target = review_target.jj({
		root = root,
		cwd = root,
		git_root = git_root,
		base = base,
		head = head,
		base_revset = base,
		head_revset = head,
		resolved_base = resolved_base,
		resolved_head = resolved_head,
		raw_base = opts.base_revset or config.options.jj.base_revset or "trunk()",
		raw_head = head == "@" and "@" or (resolved_head and resolved_head:sub(1, 12) or head),
		fallback_notes = fallback_notes,
		current_fallback = fallback_notes ~= nil,
	})
	return item({
		id = target.current_fallback and "jj-current-fallback" or "jj-current-trunk",
		label = target.current_fallback and "Previous mutable jj change" or "Current jj change",
		description = target.current_fallback and (warnings[1] or "Fallback from empty working-copy commit")
			or "trunk() → current jj change",
		badge = "jj",
		target = target,
		summary_lines = jj.diff_summary(base, head, root),
		warnings = warnings,
	}),
		nil
end

function M.current_target(opts)
	opts = opts or {}
	local cwd = cwd_or_default(opts.cwd)
	local prefer_jj = opts.prefer_jj
	if prefer_jj == nil then
		prefer_jj = config.options.jj.prefer_jj_for_local ~= false
	end
	if prefer_jj and config.options.jj.enabled then
		local ok_jj, jj = pcall(require, "unified_review.integrations.jj")
		if ok_jj and jj.available() and jj.is_workspace(cwd) then
			return jj_current_target(cwd, opts)
		end
	end

	local discovered, err = M.discover(vim.tbl_extend("force", opts, { prefer_jj = false }))
	if not discovered then
		return nil, err
	end
	local preferred_ids = { "git-working", "pr-base", "git-origin/main", "git-origin/master", "git-last-commit" }
	for _, id in ipairs(preferred_ids) do
		for _, candidate in ipairs(discovered.items or {}) do
			if candidate.id == id and candidate.target and not candidate.disabled then
				return candidate, nil
			end
		end
	end
	for _, candidate in ipairs(discovered.items or {}) do
		if candidate.target and not candidate.disabled then
			return candidate, nil
		end
	end
	return nil, { message = "No current review target was found" }
end

function M.discover(opts)
	opts = opts or {}
	local cwd = cwd_or_default(opts.cwd)
	if opts.prefer_jj ~= false and config.options.jj.enabled then
		local ok_jj, jj = pcall(require, "unified_review.integrations.jj")
		if ok_jj and jj.available() and jj.is_workspace(cwd) then
			local result, err = discover_jj(cwd)
			if result then
				return result, nil
			end
			return nil, err
		end
	end
	local result, err = discover_git(cwd)
	if result then
		return result, nil
	end
	local items = {}
	append_meta_items(
		items,
		"none",
		nil,
		{ empty_message = "No Git or jj repository was detected. Use a custom target after changing directories." }
	)
	return {
		mode = "none",
		provider = "none",
		cwd = cwd,
		root = nil,
		items = items,
		warnings = { err and (err.message or err.stderr) or "No Git or jj repository detected" },
	},
		nil
end

local function split_args(input)
	input = trim(input)
	if input == "" then
		return {}
	end
	return vim.split(input, "%s+", { trimempty = true })
end

function M.normalize_github_pr(input, opts)
	opts = opts or {}
	local ok_gh, gh = pcall(require, "unified_review.integrations.gh")
	if not ok_gh then
		return nil, { message = "GitHub integration failed to load" }
	end
	local ref, err = gh.parse_pr_ref(input)
	if not ref then
		return nil, err
	end
	return review_target.github_pr({
		cwd = opts.cwd or opts.root or vim.fn.getcwd(),
		root = opts.root or opts.cwd or vim.fn.getcwd(),
		number = ref.number,
		url = ref.url,
		owner = ref.owner,
		repo = ref.repo,
	}),
		nil
end

function M.open_pull_requests(opts)
	opts = opts or {}
	local ok_gh, gh = pcall(require, "unified_review.integrations.gh")
	if not ok_gh then
		return nil, { message = "GitHub integration failed to load" }
	end
	local cwd = opts.cwd or opts.root or vim.fn.getcwd()
	local prs, err = gh.list_open_prs(cwd, { command = config.options.github.transport_command, limit = opts.limit })
	if not prs then
		return nil, err
	end
	local result = {}
	for _, pr in ipairs(prs or {}) do
		local author = pr.author and pr.author.login or pr.author
		table.insert(result, {
			number = pr.number,
			url = pr.url,
			title = pr.title,
			is_draft = pr.isDraft,
			base_name = pr.baseRefName,
			head_name = pr.headRefName,
			author = author,
			target = review_target.github_pr({
				cwd = cwd,
				root = cwd,
				number = pr.number,
				url = pr.url,
				title = pr.title,
				raw_base = pr.baseRefName,
				raw_head = pr.headRefName,
			}),
		})
	end
	return result, nil
end

function M.normalize_custom(input, opts)
	opts = opts or {}
	local mode = opts.mode or "git"
	local cwd = opts.cwd or opts.root or vim.fn.getcwd()
	input = trim(input)
	if input == "" then
		return nil, { message = "Enter a review target or range." }
	end
	if mode == "jj" then
		local ok_jj, jj = pcall(require, "unified_review.integrations.jj")
		if not ok_jj then
			return nil, { message = "jj integration failed to load" }
		end
		local base, head = input:match("^(.-)%.%.%.(.*)$")
		if not base then
			base, head = input:match("^(.-)%.%.(.*)$")
		end
		if not base then
			base, head = input, "@"
		end
		if head == "" or head == nil then
			head = "@"
		end
		base = jj.normalize_remote_alias(trim(base), cwd)
		head = jj.normalize_remote_alias(trim(head), cwd)
		local resolved_base, base_err = jj.resolve_revset(base, cwd)
		if not resolved_base then
			return nil,
				{
					message = "Unable to resolve jj base `" .. base .. "`: " .. command_error_message(base_err),
				}
		end
		local resolved_head, head_err = jj.resolve_revset(head, cwd)
		if not resolved_head then
			return nil,
				{
					message = "Unable to resolve jj head `" .. head .. "`: " .. command_error_message(head_err),
				}
		end
		return review_target.jj({
			root = opts.root or cwd,
			git_root = opts.git_root,
			base = base,
			head = head,
			base_revset = base,
			head_revset = head,
			resolved_base = resolved_base,
			resolved_head = resolved_head,
			raw_input = input,
		}),
			nil
	end

	local args = split_args(input)
	local base, head, range_kind = git.parse_range(args)
	if #args == 1 and not input:find("%.%.", 1, false) then
		base, head, range_kind = args[1], "HEAD", "three_dot"
	end
	if not base or base == "" then
		return nil, { message = "Git base ref is required." }
	end
	return review_target.local_git({
		cwd = cwd,
		root = opts.root,
		base = base,
		head = head or "HEAD",
		range_kind = range_kind,
		raw_input = input,
	}),
		nil
end

function M.recent_commits(opts)
	opts = opts or {}
	local mode = opts.mode or "git"
	local cwd = opts.cwd or opts.root or vim.fn.getcwd()
	if mode == "jj" then
		local ok_jj, jj = pcall(require, "unified_review.integrations.jj")
		if not ok_jj then
			return nil, { message = "jj integration failed to load" }
		end
		return jj.recent_commits(cwd, opts.limit)
	end
	return git.recent_commits(cwd, opts.limit)
end

function M.validate_commit_range(commits, base_index, head_index)
	if not commits or #commits == 0 then
		return nil, { message = "No commits are available for range selection." }
	end
	if not base_index or not head_index then
		return nil, { message = "Choose both a base and a head commit." }
	end
	if not commits[base_index] or not commits[head_index] then
		return nil, { message = "Selected range endpoint is no longer visible." }
	end
	if base_index == head_index then
		return nil, { message = "Base and head must be different commits." }
	end
	-- Recent commits are rendered newest first. A valid range has an older base
	-- (larger index) and a newer head (smaller index).
	if head_index > base_index then
		return nil, { message = "Head must be newer than base." }
	end
	return {
		base = commits[base_index],
		head = commits[head_index],
		base_index = base_index,
		head_index = head_index,
	},
		nil
end

function M.target_from_commit_range(commits, base_index, head_index, opts)
	opts = opts or {}
	local range, err = M.validate_commit_range(commits, base_index, head_index)
	if not range then
		return nil, err
	end
	if opts.mode == "jj" or range.base.provider == "jj" or range.head.provider == "jj" then
		return review_target.jj({
			root = opts.root or opts.cwd,
			git_root = opts.git_root,
			base = range.base.oid,
			head = range.head.oid,
			base_revset = range.base.oid,
			head_revset = range.head.oid,
			resolved_base = range.base.oid,
			resolved_head = range.head.oid,
			raw_base = range.base.short_id,
			raw_head = range.head.short_id,
		}),
			nil
	end
	return review_target.local_git({
		cwd = opts.root or opts.cwd,
		root = opts.root,
		base = range.base.oid,
		head = range.head.oid,
		range_kind = "two_dot",
		raw_base = range.base.short_id,
		raw_head = range.head.short_id,
	}),
		nil
end

return M
