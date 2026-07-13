local M = {}

local function run(root, args)
	local command = vim.list_extend({ "jj" }, args)
	local result = vim.system(command, { cwd = root, text = true }):wait()
	if result.code ~= 0 then
		error((result.stderr or "jj failed") .. "\n" .. table.concat(command, " "))
	end
	return result.stdout or ""
end

local function run_git(root, args)
	local command = vim.list_extend({ "git", "-C", root }, args)
	local result = vim.system(command, { text = true }):wait()
	if result.code ~= 0 then
		error((result.stderr or "git failed") .. "\n" .. table.concat(command, " "))
	end
	return result.stdout or ""
end

function M.available()
	return vim.fn.executable("jj") == 1
end

function M.create()
	if not M.available() then
		pending("jj executable is not available")
	end
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	run(root, {
		"--config",
		"signing.backend=none",
		"--config",
		"signing.behavior=drop",
		"--config",
		"user.name=Unified Review Tests",
		"--config",
		"user.email=unified-review@example.invalid",
		"git",
		"init",
		"--colocate",
		".",
	})
	run(root, { "config", "set", "--repo", "signing.backend", "none" })
	run(root, { "config", "set", "--repo", "signing.behavior", "drop" })
	run(root, { "config", "set", "--repo", "user.name", "Unified Review Tests" })
	run(root, { "config", "set", "--repo", "user.email", "unified-review@example.invalid" })
	return root
end

function M.write(root, path, lines)
	local full_path = root .. "/" .. path
	vim.fn.mkdir(vim.fn.fnamemodify(full_path, ":h"), "p")
	vim.fn.writefile(lines, full_path)
end

function M.describe(root, message)
	run(root, { "describe", "-m", message })
end

function M.new(root)
	run(root, { "new" })
end

function M.add_workspace(root)
	local workspace = vim.fn.tempname()
	run(root, { "workspace", "add", workspace })
	return workspace
end

function M.bookmark(root, name, revset)
	run(root, { "bookmark", "set", name, "-r", revset or "@" })
end

function M.remote_bookmark(root, name, revset)
	local oid = M.rev_parse(root, revset or "@")
	run_git(root, { "update-ref", "refs/remotes/origin/" .. name, oid })
	-- Import the synthetic remote ref so jj revsets such as main@origin are real.
	run(root, { "bookmark", "list", "--all" })
end

function M.rev_parse(root, revset)
	return (
		run(root, { "log", "--no-graph", "-r", revset, "--limit", "1", "-T", 'commit_id ++ "\\n"' }):gsub("%s+$", "")
	)
end

M.run = run
M.run_git = run_git

return M
