local anchors = require("unified_review.util.anchors")
local line_map = require("unified_review.util.line_map")

describe("anchors", function()
	it("creates content anchors with stable selected-text hashes", function()
		local anchor = anchors.content_anchor({
			hunk_header = "@@ -1 +1 @@",
			before = { "before" },
			selected = { "one", "two" },
			after = { "after" },
			base_id = "base",
			head_id = "head",
		})

		assert.are.equal("@@ -1 +1 @@", anchor.hunk_header)
		assert.are.same({ "before" }, anchor.before)
		assert.are.same({ "one", "two" }, anchor.selected)
		assert.are.same({ "after" }, anchor.after)
		assert.are.equal("base", anchor.base_id)
		assert.are.equal("head", anchor.head_id)
		assert.are.equal(vim.fn.sha256("one\ntwo"), anchor.excerpt_hash)
	end)

	it("defaults missing context arrays to empty tables", function()
		local anchor = anchors.content_anchor({})

		assert.are.same({}, anchor.before)
		assert.are.same({}, anchor.selected)
		assert.are.same({}, anchor.after)
		assert.are.equal(vim.fn.sha256(""), anchor.excerpt_hash)
	end)
end)

describe("line map", function()
	it("extracts stable hunk line coordinates", function()
		local rows = line_map.hunk_lines({
			lines = {
				{ kind = "context", old_line = 1, new_line = 1, content = "same" },
				{ kind = "delete", old_line = 2, content = "old" },
				{ kind = "add", new_line = 2, content = "new" },
			},
		})

		assert.are.same({ kind = "context", old_line = 1, new_line = 1 }, rows[1])
		assert.are.same({ kind = "delete", old_line = 2 }, rows[2])
		assert.are.same({ kind = "add", new_line = 2 }, rows[3])
	end)

	it("handles hunks without lines", function()
		assert.are.same({}, line_map.hunk_lines({}))
	end)
end)
