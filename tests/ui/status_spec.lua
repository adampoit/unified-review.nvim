local status = require("unified_review.ui.status")

describe("status module", function()
	it("formats a session summary with file and thread counts", function()
		local session = {
			target = { base_ref = "origin/main" },
			files = { {}, {}, {} },
			threads = {
				{ state = "open", comments = {} },
				{
					state = "open",
					comments = { { state = "draft" }, { state = "draft", metadata = { github = { id = "c1" } } } },
				},
				{ state = "resolved", comments = {} },
				{ state = "stale", comments = {} },
			},
		}

		local s = status.summary(session)
		assert(s, "expected a summary")
		assert.are.equal(3, s.files)
		assert.are.equal(4, s.threads)
		assert.are.equal(2, s.open)
		assert.are.equal(2, s.drafts)
		assert.are.equal(1, s.local_drafts)
		assert.are.equal(1, s.remote_drafts)
		assert.are.equal(1, s.stale)

		local formatted = status.format(session)
		assert.matches("origin/main", formatted)
		assert.matches("3 file", formatted)
		assert.matches("T2", formatted)
		assert.matches("D2", formatted)
		assert.matches("S1", formatted)
	end)

	it("handles sessions with no threads", function()
		local session = {
			target = { base = "abc123" },
			files = { {} },
			threads = {},
		}

		local s = status.summary(session)
		assert(s, "expected a summary")
		assert.are.equal(1, s.files)
		assert.are.equal(0, s.threads)

		local formatted = status.format(session)
		assert.matches("abc123", formatted)
		-- Thread/draft badges only appear when there are threads.
		assert.not_matches("T%d", formatted)
		assert.not_matches("D%d", formatted)
	end)

	it("returns nil summary for nil session", function()
		assert.is_nil(status.summary(nil))
		assert.matches("no active", status.format(nil))
	end)

	it("sets tab label variable", function()
		local session = {
			target = { base = "main" },
			files = { {} },
			threads = {},
		}
		local tab = vim.api.nvim_get_current_tabpage()
		status.set_tab_label(tab, session)
		assert.is_not_nil(vim.api.nvim_tabpage_get_var(tab, "review_label"))
	end)
end)
