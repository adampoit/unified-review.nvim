local M = {}

local cache = {}

local function path_join(...)
	return table.concat({ ... }, "/")
end

local function repo_root()
	local source = debug.getinfo(1, "S").source:gsub("^@", "")
	if source:sub(1, 1) == "/" then
		return source:gsub("/tests/helpers/diff_builder%.lua$", "")
	end
	return vim.loop.cwd()
end

local function script_path()
	return path_join(repo_root(), "tests", "dsl", "build-diff.ts")
end

local function encode_json(value)
	if vim.json and vim.json.encode then
		return vim.json.encode(value)
	end
	return vim.fn.json_encode(value)
end

local function decode_json(value)
	if vim.json and vim.json.decode then
		return vim.json.decode(value)
	end
	return vim.fn.json_decode(value)
end

local function op(kind, label, count_or_lines)
	local result = { kind = kind, label = label }
	if type(count_or_lines) == "table" then
		result.lines = count_or_lines
	else
		result.count = count_or_lines or 1
	end
	return result
end

function M.ctx(label, count_or_lines)
	return op("context", label, count_or_lines)
end

function M.add(label, count_or_lines)
	return op("added", label, count_or_lines)
end

function M.del(label, count_or_lines)
	return op("deleted", label, count_or_lines)
end

function M.hunk(ops, opts)
	opts = opts or {}
	return {
		ops = ops,
		gapBefore = opts.gapBefore or opts.gap_before or 0,
	}
end

function M.file(path, ops_or_hunks)
	local has_hunks = false
	for _, entry in ipairs(ops_or_hunks) do
		if entry.ops then
			has_hunks = true
			break
		end
	end
	if has_hunks then
		return { path = path, hunks = ops_or_hunks }
	end
	return { path = path, hunks = { M.hunk(ops_or_hunks) } }
end

function M.diff(files)
	local input = encode_json({ files = files })
	if cache[input] then
		return cache[input]
	end

	local result = vim.system({ vim.env.NODE_BINARY or "node", script_path() }, { text = true, stdin = input }):wait()
	if result.code ~= 0 then
		error(table.concat({
			"diff DSL builder failed",
			result.stderr or "",
			result.stdout or "",
		}, "\n"))
	end

	local scenario = decode_json(result.stdout)
	cache[input] = scenario
	return scenario
end

return M
