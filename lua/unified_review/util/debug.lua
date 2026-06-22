local M = {}

local MAX_LINES = 400

local redactions = {
	paths = {},
	urls = {},
	path_count = 0,
	url_count = 0,
}

local function log_path()
	local dir = vim.fn.stdpath("state") .. "/unified-review"
	pcall(vim.fn.mkdir, dir, "p")
	return dir .. "/debug.log"
end

local function path_label(value)
	value = tostring(value or "")
	local existing = redactions.paths[value]
	if existing then
		return existing
	end
	redactions.path_count = redactions.path_count + 1
	local normalized = value:gsub("\\", "/")
	local basename = normalized:match("([^/]+)$") or ""
	local ext = basename:match("(%.%w+)$") or ""
	local label = string.format("<path:%d%s>", redactions.path_count, ext)
	redactions.paths[value] = label
	return label
end

local function url_label(value)
	value = tostring(value or "")
	local existing = redactions.urls[value]
	if existing then
		return existing
	end
	redactions.url_count = redactions.url_count + 1
	local host = value:match("^https?://([^/]+)")
	local label = host and string.format("<url:%d:%s>", redactions.url_count, host)
		or string.format("<url:%d>", redactions.url_count)
	redactions.urls[value] = label
	return label
end

local function string_looks_path_like(value)
	return value:find("/", 1, true) ~= nil or value:find("\\", 1, true) ~= nil or value:match("^%w[%w+.-]*://") ~= nil
end

local function key_suggests_path(key)
	key = tostring(key or ""):lower()
	return key:find("path", 1, true) ~= nil
		or key:find("root", 1, true) ~= nil
		or key == "buf_name"
		or key == "current_file"
		or key == "original_path"
		or key == "modified_path"
end

local function redact_string(value, key)
	if value:match("^https?://") then
		return url_label(value)
	end
	if key_suggests_path(key) or string_looks_path_like(value) then
		return path_label(value)
	end
	return value
end

local function sanitize(value, key, seen)
	local value_type = type(value)
	if value_type == "string" then
		return redact_string(value, key)
	end
	if value_type ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return "<cycle>"
	end
	seen[value] = true
	local result = {}
	for child_key, child_value in pairs(value) do
		result[child_key] = sanitize(child_value, child_key, seen)
	end
	seen[value] = nil
	return result
end

local function safe_json(value)
	local ok, encoded = pcall(vim.json.encode, sanitize(value))
	if ok then
		return encoded
	end
	return vim.inspect(sanitize(value))
end

local function trim_file(path)
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok or #lines <= MAX_LINES then
		return
	end
	local start = math.max(1, #lines - MAX_LINES + 1)
	pcall(vim.fn.writefile, vim.list_slice(lines, start, #lines), path)
end

function M.path()
	return log_path()
end

function M.event(name, data)
	local path = log_path()
	local line = safe_json({
		time = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		name = name,
		data = data or {},
	})
	pcall(vim.fn.writefile, { line }, path, "a")
	trim_file(path)
end

function M.clear()
	redactions.paths = {}
	redactions.urls = {}
	redactions.path_count = 0
	redactions.url_count = 0
	pcall(vim.fn.writefile, {}, log_path())
end

function M.tail(count)
	count = count or MAX_LINES
	local ok, lines = pcall(vim.fn.readfile, log_path())
	if not ok then
		return {}
	end
	if #lines <= count then
		return lines
	end
	return vim.list_slice(lines, #lines - count + 1, #lines)
end

function M.copy(count)
	local text = table.concat(M.tail(count), "\n")
	vim.fn.setreg("+", text)
	vim.fn.setreg('"', text)
	return text
end

return M
