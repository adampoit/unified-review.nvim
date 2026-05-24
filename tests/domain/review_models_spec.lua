local changed_file = require("unified_review.domain.changed_file")
local diff_hunk = require("unified_review.domain.diff_hunk")
local diff_line = require("unified_review.domain.diff_line")
local review_comment = require("unified_review.domain.review_comment")
local review_target = require("unified_review.domain.review_target")
local review_thread = require("unified_review.domain.review_thread")

describe("review domain models", function()
	it("creates review targets", function()
		assert.are.same({
			kind = "local_git",
			base = "origin/main",
			head = "HEAD",
		}, review_target.new({ kind = "local_git", base = "origin/main", head = "HEAD" }))
	end)

	it("creates changed files", function()
		local file = changed_file.new({ path = "a.lua", status = "added" })
		assert.are.equal("a.lua", file.path)
		assert.are.equal("added", file.status)
		assert.are.same({}, file.hunks)
	end)

	it("creates diff hunks and lines", function()
		local line = diff_line.new({ kind = "added", new_line = 5, text = "local x = 1" })
		local hunk = diff_hunk.new({ header = "@@ -0,0 +5,1 @@", old_start = 0, new_start = 5, lines = { line } })

		assert.are.equal("added", hunk.lines[1].kind)
		assert.are.equal(5, hunk.lines[1].new_line)
	end)

	it("creates comments and threads with ids", function()
		local comment = review_comment.new({ body = "Looks good" })
		local thread = review_thread.new({
			target = { kind = "line", path = "a.lua", side = "right", line = 5 },
			comments = { comment },
		})

		assert.matches("^comment%-", comment.id)
		assert.matches("^thread%-", thread.id)
		assert.are.equal("Looks good", thread.comments[1].body)
	end)

	it("validates enums", function()
		assert.has_error(function()
			changed_file.new({ path = "a.lua", status = "unknown" })
		end, "status must be one of: added, modified, deleted, renamed, copied, type_changed, binary")
	end)
end)
