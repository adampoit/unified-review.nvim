local M = {}

M.defaults = {
	codediff = {
		auto_attach = true,
	},
	ui = {
		layout = {
			file_panel_width = 36,
			diff = "side_by_side",
		},
		tabline_format = "full", -- "full", "compact", or false to disable
		signs = {
			thread = "UnifiedReviewThread",
			resolved = "UnifiedReviewResolved",
			draft = "UnifiedReviewDraft",
			stale = "UnifiedReviewStale",
			suggestion = "UnifiedReviewSuggestion",
		},
		highlights = {
			thread = "UnifiedReviewThread",
			resolved = "UnifiedReviewResolved",
			draft = "UnifiedReviewDraft",
			stale = "UnifiedReviewStale",
			suggestion = "UnifiedReviewSuggestion",
			picker = "UnifiedReviewPicker",
			picker_selected = "UnifiedReviewPickerSelected",
			picker_badge = "UnifiedReviewPickerBadge",
		},
		keymaps = {
			enabled = true,
			next_file = "]f",
			previous_file = "[f",
			next_hunk = "]h",
			previous_hunk = "[h",
			next_thread = "]t",
			previous_thread = "[t",
			comment = "<leader>rc",
			reply = "<leader>rr",
			threads = "<leader>rt",
			summary = "<leader>rS",
			toggle_export = "<leader>re",
			close = "q",
			select_file = "<CR>",
		},
	},
	local_git = {
		base_ref = "origin/main",
		auto_copy_on_add = false,
		head_ref = "HEAD",
		state_dir = vim.fn.stdpath("state") .. "/unified-review",
	},
	jj = {
		enabled = true,
		base_revset = "trunk()",
		prefer_jj_for_local = true,
		editable_checkout_strategy = "never",
	},
	github = {
		checkout_mode = "none",
		transport_command = "gh",
		no_checkout_readonly = true,
	},
}

M.options = vim.deepcopy(M.defaults)

local function migrate_legacy_ui_opts(opts)
	opts = vim.deepcopy(opts or {})
	local legacy = opts.local_git or {}
	for _, key in ipairs({ "layout", "tabline_format", "signs", "highlights", "keymaps" }) do
		if legacy[key] ~= nil then
			opts.ui = opts.ui or {}
			if type(legacy[key]) == "table" then
				opts.ui[key] = vim.tbl_deep_extend("force", opts.ui[key] or {}, legacy[key])
			else
				opts.ui[key] = legacy[key]
			end
			legacy[key] = nil
		end
	end
	return opts
end

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), migrate_legacy_ui_opts(opts))
	return M.options
end

return M
