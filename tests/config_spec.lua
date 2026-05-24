local config = require("unified_review.config")

describe("config", function()
	after_each(function()
		config.setup({})
	end)

	it("starts from defaults", function()
		local opts = config.setup({})
		assert.are.equal("origin/main", opts.local_git.base_ref)
		assert.are.equal("HEAD", opts.local_git.head_ref)
		assert.is_true(opts.ui.keymaps.enabled)
	end)

	it("deep-merges partial overrides without losing nested defaults", function()
		local opts = config.setup({
			local_git = { base_ref = "main" },
			ui = {
				layout = { file_panel_width = 50 },
				keymaps = { comment = "gc" },
			},
		})

		assert.are.equal("main", opts.local_git.base_ref)
		assert.are.equal("HEAD", opts.local_git.head_ref)
		assert.are.equal(50, opts.ui.layout.file_panel_width)
		assert.are.equal("side_by_side", opts.ui.layout.diff)
		assert.are.equal("gc", opts.ui.keymaps.comment)
		assert.are.equal("]f", opts.ui.keymaps.next_file)
	end)

	it("migrates legacy local_git UI options", function()
		local opts = config.setup({ local_git = { keymaps = { comment = "gc" } } })

		assert.are.equal("gc", opts.ui.keymaps.comment)
		assert.is_nil(opts.local_git.keymaps)
	end)

	it("does not mutate defaults when options are changed", function()
		config.setup({ ui = { keymaps = { comment = "gc" } } })

		assert.are.equal("<leader>rc", config.defaults.ui.keymaps.comment)
	end)
end)
