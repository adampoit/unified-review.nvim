local changed_file = require("unified_review.domain.changed_file")
local diff_hunk = require("unified_review.domain.diff_hunk")
local diff_line = require("unified_review.domain.diff_line")

local M = {}

local function strip_prefix(path)
	if not path then
		return nil
	end
	return path:gsub('^"', ""):gsub('"$', ""):gsub("^[ab]/", "")
end

local function parse_count(value)
	return tonumber(value) or 1
end

local function status_from_headers(headers)
	if headers.binary then
		return "binary"
	elseif headers.rename_from then
		return "renamed"
	elseif headers.copy_from then
		return "copied"
	elseif headers.new_file then
		return "added"
	elseif headers.deleted_file then
		return "deleted"
	end
	return "modified"
end

local function finalize_file(files, current)
	if not current then
		return
	end
	local path = current.path or strip_prefix(current.to_path) or strip_prefix(current.from_path)
	if path == "/dev/null" then
		path = strip_prefix(current.from_path)
	end
	local additions = 0
	local deletions = 0
	for _, parsed_hunk in ipairs(current.hunks or {}) do
		for _, line in ipairs(parsed_hunk.lines or {}) do
			if line.kind == "added" then
				additions = additions + 1
			elseif line.kind == "deleted" then
				deletions = deletions + 1
			end
		end
	end
	table.insert(
		files,
		changed_file.new({
			path = path,
			old_path = current.old_path,
			status = status_from_headers(current.headers),
			additions = additions,
			deletions = deletions,
			hunks = current.hunks,
			raw_patch = table.concat(current.raw, "\n"),
			metadata = current.headers,
		})
	)
end

function M.parse(patch)
	local files = {}
	local current
	local hunk
	local old_line
	local new_line

	for raw_line in (patch .. "\n"):gmatch("(.-)\n") do
		local from_path, to_path = raw_line:match("^diff %-%-git a/(.-) b/(.*)$")
		if from_path then
			finalize_file(files, current)
			current = {
				from_path = from_path,
				to_path = to_path,
				path = strip_prefix(to_path),
				hunks = {},
				headers = {},
				raw = { raw_line },
			}
			hunk = nil
		else
			if current then
				table.insert(current.raw, raw_line)

				if raw_line:match("^new file mode ") then
					current.headers.new_file = true
				elseif raw_line:match("^deleted file mode ") then
					current.headers.deleted_file = true
				elseif raw_line:match("^Binary files ") or raw_line == "GIT binary patch" then
					current.headers.binary = true
				elseif raw_line:match("^rename from ") then
					current.headers.rename_from = raw_line:sub(13)
					current.old_path = current.headers.rename_from
				elseif raw_line:match("^rename to ") then
					current.headers.rename_to = raw_line:sub(11)
					current.path = current.headers.rename_to
				elseif raw_line:match("^copy from ") then
					current.headers.copy_from = raw_line:sub(11)
					current.old_path = current.headers.copy_from
				elseif raw_line:match("^copy to ") then
					current.headers.copy_to = raw_line:sub(9)
					current.path = current.headers.copy_to
				elseif raw_line:match("^%-%-%- ") then
					current.from_path = strip_prefix(raw_line:sub(5))
				elseif raw_line:match("^%+%+%+ ") then
					local path = strip_prefix(raw_line:sub(5))
					if path ~= "/dev/null" then
						current.path = path
					end
				else
					local old_start, old_count, parsed_new_start, new_count =
						raw_line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
					if old_start then
						old_line = tonumber(old_start)
						new_line = tonumber(parsed_new_start)
						hunk = diff_hunk.new({
							header = raw_line,
							old_start = old_line,
							old_count = parse_count(old_count),
							new_start = new_line,
							new_count = parse_count(new_count),
							lines = {},
						})
						table.insert(current.hunks, hunk)
					elseif hunk then
						local marker = raw_line:sub(1, 1)
						local text = raw_line:sub(2)
						if marker == "+" then
							table.insert(
								hunk.lines,
								diff_line.new({ kind = "added", new_line = new_line, text = text, raw = raw_line })
							)
							new_line = new_line + 1
						elseif marker == "-" then
							table.insert(
								hunk.lines,
								diff_line.new({ kind = "deleted", old_line = old_line, text = text, raw = raw_line })
							)
							old_line = old_line + 1
						elseif marker == " " then
							table.insert(
								hunk.lines,
								diff_line.new({
									kind = "context",
									old_line = old_line,
									new_line = new_line,
									text = text,
									raw = raw_line,
								})
							)
							old_line = old_line + 1
							new_line = new_line + 1
						end
					end
				end
			end
		end
	end

	finalize_file(files, current)
	return files
end

return M
