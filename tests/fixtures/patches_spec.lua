local parser = require("unified_review.util.patch_parse")

local function read_fixture(name)
	local fixture_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h") .. "/patches"
	local path = fixture_dir .. "/" .. name .. ".diff"
	local content = table.concat(vim.fn.readfile(path), "\n")
	assert.is_not_nil(content)
	assert.is_not_equal("", content)
	return content
end

describe("patch parser fixtures", function()
	it("parses files with spaces in paths", function()
		local files = parser.parse(read_fixture("spaces_in_path"))

		assert.are.equal(2, #files)

		assert.are.equal("path with spaces/file name.lua", files[1].path)
		assert.are.equal("modified", files[1].status)
		-- fixture: -local b = 2, +local b = 3, +local c = 4 → 2 additions, 1 deletion
		assert.are.equal(2, files[1].additions)
		assert.are.equal(1, files[1].deletions)
		assert.are.equal(1, #files[1].hunks)

		assert.are.equal("src/another path/read me.md", files[2].path)
		assert.are.equal("modified", files[2].status)
		assert.are.equal(1, files[2].additions)
		assert.are.equal(1, files[2].deletions)
	end)

	it("parses binary file markers", function()
		local files = parser.parse(read_fixture("binary_file"))

		assert.are.equal(3, #files)

		-- new binary file
		assert.are.equal("assets/image.png", files[1].path)
		assert.are.equal("binary", files[1].status)
		assert.are.equal(0, #files[1].hunks)

		-- modified binary file
		assert.are.equal("assets/icon.png", files[2].path)
		assert.are.equal("binary", files[2].status)
		assert.are.equal(0, #files[2].hunks)

		-- deleted binary file
		assert.are.equal("docs/screenshot.png", files[3].path)
		assert.are.equal("binary", files[3].status)
		assert.are.equal(0, #files[3].hunks)
	end)

	it("parses renamed files and copy/modify combinations", function()
		local files = parser.parse(read_fixture("rename_copy"))

		-- The copy target (lib/copy_utils.lua) creates a separate file entry with no hunks;
		-- the modified source (lib/utils.lua) is also a separate entry. Total: 3.
		assert.are.equal(3, #files)

		-- rename
		assert.are.equal("lib/new_name.lua", files[1].path)
		assert.are.equal("lib/old_name.lua", files[1].old_path)
		assert.are.equal("renamed", files[1].status)

		-- copy target should preserve copy metadata rather than looking like a plain modification.
		assert.are.equal("lib/copy_utils.lua", files[2].path)
		assert.are.equal("lib/utils.lua", files[2].old_path)
		assert.are.equal("copied", files[2].status)

		-- modified source after copy
		assert.are.equal("lib/utils.lua", files[3].path)
		assert.are.equal("modified", files[3].status)
		assert.are.equal(2, files[3].additions)
		assert.are.equal(1, files[3].deletions)
	end)

	it("parses type changes (mode, symlink, submodule)", function()
		local files = parser.parse(read_fixture("type_change"))

		-- The parser handles type changes as best-effort; mode-only changes
		-- (no diff content) produce files with empty hunks.
		assert.is_true(#files >= 2, "expected at least 2 files from type_change fixture")

		-- Find the mode-change file (bin/script.sh)
		local mode_change_file
		for _, f in ipairs(files) do
			if f.path == "bin/script.sh" then
				mode_change_file = f
				break
			end
		end
		assert.is_not_nil(mode_change_file)
		assert.are.equal(0, #mode_change_file.hunks)
		assert.is_not_nil(mode_change_file.raw_patch)

		-- Find the submodule change
		local submodule_file
		for _, f in ipairs(files) do
			if f.path == "submodule" then
				submodule_file = f
				break
			end
		end
		assert.is_not_nil(submodule_file)
		assert.is_true(#submodule_file.hunks > 0)
	end)

	it("parses empty-file creation and deletion", function()
		local files = parser.parse(read_fixture("empty_file"))

		assert.are.equal(3, #files)

		-- new empty file (no hunks)
		assert.are.equal("new_empty.lua", files[1].path)
		assert.are.equal("added", files[1].status)
		assert.are.equal(0, #files[1].hunks)
		assert.are.equal(0, files[1].additions)
		assert.are.equal(0, files[1].deletions)

		-- existing file emptied (has hunks showing deletions)
		assert.are.equal("existing_to_empty.lua", files[2].path)
		assert.are.equal("modified", files[2].status)
		assert.are.equal(0, files[2].additions)
		assert.are.equal(3, files[2].deletions)

		-- deleted file
		assert.are.equal("delete_me.lua", files[3].path)
		assert.are.equal("deleted", files[3].status)
		assert.are.equal(0, files[3].additions)
		assert.are.equal(2, files[3].deletions)
	end)
end)
