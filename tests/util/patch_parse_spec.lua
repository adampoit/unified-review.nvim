local parser = require("unified_review.util.patch_parse")
local diff_builder = require("helpers.diff_builder")

local diff = diff_builder.diff
local file = diff_builder.file
local hunk = diff_builder.hunk
local ctx = diff_builder.ctx
local add = diff_builder.add
local del = diff_builder.del

local function summarize_files(files)
	local summary = {}
	for _, parsed_file in ipairs(files) do
		table.insert(summary, {
			path = parsed_file.path,
			status = parsed_file.status,
			additions = parsed_file.additions,
			deletions = parsed_file.deletions,
			hunks = #parsed_file.hunks,
		})
	end
	return summary
end

describe("patch_parse", function()
	it("parses modified files and hunk lines", function()
		local scenario = diff({
			file("src/right-longer-replacement.txt", {
				ctx("before", 2),
				del("old", 1),
				add("new", 3),
				ctx("after", 2),
			}),
		})
		local files = parser.parse(scenario.patch)

		assert.are.same({
			{
				path = "src/right-longer-replacement.txt",
				status = "modified",
				additions = 3,
				deletions = 1,
				hunks = 1,
			},
		}, summarize_files(files))
		assert.are.equal(1, files[1].hunks[1].lines[1].old_line)
		assert.are.equal(3, files[1].hunks[1].lines[3].old_line)
		assert.are.equal(3, files[1].hunks[1].lines[4].new_line)
		assert.are.equal("added", files[1].hunks[1].lines[5].kind)
	end)

	local cases = {
		{
			name = "addition between context",
			scenario = diff({
				file("src/addition-between-context.txt", {
					ctx("before", 2),
					add("target", 2),
					ctx("after", 2),
				}),
			}),
			expected = {
				{
					path = "src/addition-between-context.txt",
					status = "modified",
					additions = 2,
					deletions = 0,
					hunks = 1,
				},
			},
		},
		{
			name = "deletion between context",
			scenario = diff({
				file("src/deletion-between-context.txt", {
					ctx("before", 2),
					del("target", 2),
					ctx("after", 2),
				}),
			}),
			expected = {
				{
					path = "src/deletion-between-context.txt",
					status = "modified",
					additions = 0,
					deletions = 2,
					hunks = 1,
				},
			},
		},
		{
			name = "equal replacement",
			scenario = diff({
				file("src/equal-replacement.txt", {
					ctx("before", 2),
					del("old", 2),
					add("new", 2),
					ctx("after", 2),
				}),
			}),
			expected = {
				{ path = "src/equal-replacement.txt", status = "modified", additions = 2, deletions = 2, hunks = 1 },
			},
		},
		{
			name = "right-longer replacement",
			scenario = diff({
				file("src/right-longer-replacement.txt", {
					ctx("before", 2),
					del("old", 1),
					add("new", 3),
					ctx("after", 2),
				}),
			}),
			expected = {
				{
					path = "src/right-longer-replacement.txt",
					status = "modified",
					additions = 3,
					deletions = 1,
					hunks = 1,
				},
			},
		},
		{
			name = "left-longer replacement",
			scenario = diff({
				file("src/left-longer-replacement.txt", {
					ctx("before", 2),
					del("old", 3),
					add("new", 1),
					ctx("after", 2),
				}),
			}),
			expected = {
				{
					path = "src/left-longer-replacement.txt",
					status = "modified",
					additions = 1,
					deletions = 3,
					hunks = 1,
				},
			},
		},
		{
			name = "adjacent delete/add blocks",
			scenario = diff({
				file("src/adjacent-delete-add-blocks.txt", {
					ctx("before", 1),
					del("old_block", 2),
					add("new_block", 2),
					ctx("after", 1),
				}),
			}),
			expected = {
				{
					path = "src/adjacent-delete-add-blocks.txt",
					status = "modified",
					additions = 2,
					deletions = 2,
					hunks = 1,
				},
			},
		},
		{
			name = "moved line shape",
			scenario = diff({
				file("src/moved-line-shape.txt", {
					ctx("before", 1),
					del("move_from", { "MOV_MOVED_PAYLOAD_001" }),
					ctx("middle", 8),
					add("move_to", { "MOV_MOVED_PAYLOAD_001" }),
					ctx("after", 1),
				}),
			}),
			expected = {
				{ path = "src/moved-line-shape.txt", status = "modified", additions = 1, deletions = 1, hunks = 1 },
			},
		},
		{
			name = "start-of-file addition",
			scenario = diff({
				file("src/start-of-file-addition.txt", {
					add("target", 2),
					ctx("after", 3),
				}),
			}),
			expected = {
				{
					path = "src/start-of-file-addition.txt",
					status = "modified",
					additions = 2,
					deletions = 0,
					hunks = 1,
				},
			},
		},
		{
			name = "end-of-file addition",
			scenario = diff({
				file("src/end-of-file-addition.txt", {
					ctx("before", 3),
					add("target", 2),
				}),
			}),
			expected = {
				{ path = "src/end-of-file-addition.txt", status = "modified", additions = 2, deletions = 0, hunks = 1 },
			},
		},
		{
			name = "end-of-file deletion",
			scenario = diff({
				file("src/end-of-file-deletion.txt", {
					ctx("before", 3),
					del("target", 2),
				}),
			}),
			expected = {
				{ path = "src/end-of-file-deletion.txt", status = "modified", additions = 0, deletions = 2, hunks = 1 },
			},
		},
		{
			name = "multi-hunk change",
			scenario = diff({
				file("src/multi-hunk-change.txt", {
					hunk({
						ctx("first_before", 2),
						del("first_old", 1),
						add("first_new", 1),
						ctx("first_after", 2),
					}),
					hunk({
						ctx("second_before", 2),
						add("second_new", 2),
						ctx("second_after", 2),
					}, { gap_before = 8 }),
				}),
			}),
			expected = {
				{ path = "src/multi-hunk-change.txt", status = "modified", additions = 3, deletions = 1, hunks = 2 },
			},
		},
		{
			name = "two-file change",
			scenario = diff({
				file("src/two-file-inline.txt", {
					ctx("inline_before", 2),
					add("inline_target", 1),
					ctx("inline_after", 2),
				}),
				file("src/two-file-other.txt", {
					ctx("other_before", 1),
					del("other_old", 1),
					add("other_new", 1),
					ctx("other_after", 1),
				}),
			}),
			expected = {
				{ path = "src/two-file-inline.txt", status = "modified", additions = 1, deletions = 0, hunks = 1 },
				{ path = "src/two-file-other.txt", status = "modified", additions = 1, deletions = 1, hunks = 1 },
			},
		},
	}

	for _, case in ipairs(cases) do
		it("parses diff shape: " .. case.name, function()
			local files = parser.parse(case.scenario.patch)

			assert.are.same(case.expected, summarize_files(files))
		end)
	end

	it("parses added and deleted files", function()
		local files = parser.parse(table.concat({
			"diff --git a/new file.lua b/new file.lua",
			"new file mode 100644",
			"--- /dev/null",
			"+++ b/new file.lua",
			"@@ -0,0 +1 @@",
			"+hello",
			"diff --git a/old.lua b/old.lua",
			"deleted file mode 100644",
			"--- a/old.lua",
			"+++ /dev/null",
			"@@ -1 +0,0 @@",
			"-bye",
		}, "\n"))

		assert.are.equal("added", files[1].status)
		assert.are.equal("new file.lua", files[1].path)
		assert.are.equal("deleted", files[2].status)
		assert.are.equal("old.lua", files[2].path)
	end)

	it("parses renamed and binary files", function()
		local files = parser.parse(table.concat({
			"diff --git a/old.lua b/new.lua",
			"similarity index 90%",
			"rename from old.lua",
			"rename to new.lua",
			"diff --git a/image.png b/image.png",
			"Binary files a/image.png and b/image.png differ",
		}, "\n"))

		assert.are.equal("renamed", files[1].status)
		assert.are.equal("old.lua", files[1].old_path)
		assert.are.equal("new.lua", files[1].path)
		assert.are.equal("binary", files[2].status)
	end)
end)
