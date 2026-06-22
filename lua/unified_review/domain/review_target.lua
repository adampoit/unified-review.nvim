local validate = require("unified_review.domain.validation")

local M = {}

M.kinds = { "local_git", "github_pr", "jj", "local_pr", "custom" }

local function copy(opts)
	return vim.deepcopy(opts or {})
end

local function with_kind(kind, opts)
	local target = copy(opts)
	target.kind = validate.one_of(target.kind or kind, "kind", M.kinds)
	return target
end

function M.new(opts)
	opts = opts or {}
	return with_kind(opts.kind or "local_git", opts)
end

function M.local_git(opts)
	local target = with_kind("local_git", opts)
	target.provider_kind = target.provider_kind or "git"
	target.base = target.base or target.base_ref
	target.head = target.head or target.head_ref or "HEAD"
	target.base_ref = target.base_ref or target.base
	target.head_ref = target.head_ref or target.head
	target.range_kind = target.range_kind or "three_dot"
	return target
end

function M.git_range(base, head, opts)
	opts = copy(opts)
	opts.base = opts.base or base
	opts.head = opts.head or head or "HEAD"
	return M.local_git(opts)
end

function M.jj(opts)
	local target = with_kind("jj", opts)
	target.provider_kind = target.provider_kind or "jj"
	target.base = target.base or target.base_revset
	target.head = target.head or target.head_revset or "@"
	target.base_revset = target.base_revset or target.base
	target.head_revset = target.head_revset or target.head
	target.range_kind = target.range_kind or "revset"
	return target
end

function M.github_pr(opts)
	local target = with_kind("github_pr", opts)
	target.provider_kind = target.provider_kind or "pr"
	return target
end

function M.github_pr_local_worktree(opts)
	local target = M.github_pr(opts)
	target.render_strategy = "local_worktree"
	target.local_worktree = true
	return target
end

function M.local_pr_base(opts)
	local target = M.local_git(opts)
	target.kind = "local_pr"
	target.provider_kind = "pr"
	return target
end

function M.custom(opts)
	local target = with_kind("custom", opts)
	target.provider_kind = target.provider_kind or "custom"
	return target
end

return M
