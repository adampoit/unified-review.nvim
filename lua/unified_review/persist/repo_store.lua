local config = require("unified_review.config")

local M = {}

local function hash(value)
	local ok, result = pcall(vim.fn.sha256, value)
	if ok and result and result ~= "" then
		return result:sub(1, 16)
	end
	return tostring(#value) .. "-" .. value:gsub("[^%w._-]", "_"):sub(-32)
end

function M.repo_id(root)
	root = vim.fn.fnamemodify(root or vim.loop.cwd() or ".", ":p")
	return vim.fn.fnamemodify(root, ":t") .. "-" .. hash(root)
end

function M.repo_dir(root, opts)
	opts = opts or {}
	local state_dir = opts.state_dir or config.options.local_git.state_dir
	return table.concat({ state_dir, M.repo_id(root) }, "/")
end

function M.ensure_repo_dir(root, opts)
	local dir = M.repo_dir(root, opts)
	vim.fn.mkdir(dir, "p")
	return dir
end

return M
