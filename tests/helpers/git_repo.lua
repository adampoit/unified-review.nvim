local M = {}

local function run(root, args)
	local result = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
	if result.code ~= 0 then
		local command = { "git", "-C", root }
		vim.list_extend(command, args)
		error(table.concat(command, " ") .. " failed: " .. (result.stderr or ""))
	end
	return result.stdout or ""
end

function M.create()
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	vim.system({ "git", "init", root }, { text = true }):wait()
	run(root, { "config", "user.email", "review-test@example.invalid" })
	run(root, { "config", "user.name", "Review Test" })
	return root
end

function M.write(root, path, lines)
	local full_path = root .. "/" .. path
	vim.fn.mkdir(vim.fn.fnamemodify(full_path, ":h"), "p")
	vim.fn.writefile(lines, full_path)
end

function M.read(root, path)
	return vim.fn.readfile(root .. "/" .. path)
end

function M.commit(root, message)
	run(root, { "add", "." })
	run(root, { "commit", "-m", message })
	return vim.trim(run(root, { "rev-parse", "HEAD" }))
end

--- Create a repo with a single changed file (original helper).
function M.changed_file()
	local root = M.create()
	M.write(root, "a.lua", { "local one = 1", "local two = 2", "return one + two" })
	local base = M.commit(root, "base")
	M.write(root, "a.lua", { "local one = 1", "local two = 22", "local three = 3", "return one + two + three" })
	local head = M.commit(root, "change")
	return { root = root, base = base, head = head, path = "a.lua" }
end

--- Create a repo with multiple files changed across two commits.
function M.multi_file()
	local root = M.create()
	M.write(root, "src/main.lua", { "local x = 1", "return x" })
	M.write(root, "src/utils.lua", { "function add(a, b) return a + b end" })
	M.write(root, "README.md", { "# Project", "", "A test project." })
	local base = M.commit(root, "initial commit")
	M.write(root, "src/main.lua", { "local x = 1", "local y = 2", "return x + y" })
	M.write(root, "src/utils.lua", { "function add(a, b) return a + b end", "function sub(a, b) return a - b end" })
	local head = M.commit(root, "add changes")
	return {
		root = root,
		base = base,
		head = head,
		files = { "src/main.lua", "src/utils.lua" },
	}
end

--- Create a repo with a rename and a new file.
function M.rename_and_new()
	local root = M.create()
	M.write(root, "old_name.lua", { "return 1" })
	M.write(root, "keep.lua", { "return 2" })
	local base = M.commit(root, "initial")
	run(root, { "mv", "old_name.lua", "new_name.lua" })
	M.write(root, "keep.lua", { "return 3" })
	M.write(root, "added.lua", { "return 4" })
	local head = M.commit(root, "rename and add")
	return {
		root = root,
		base = base,
		head = head,
		files = { "new_name.lua", "keep.lua", "added.lua" },
	}
end

return M
