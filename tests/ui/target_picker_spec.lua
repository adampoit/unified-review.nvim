local discovery = require("unified_review.session.target_discovery")
local picker = require("unified_review.ui.target_picker")

local function picker_state(overrides)
	return vim.tbl_deep_extend("force", {
		mode = "list",
		width = 72,
		height = 18,
		list_height = 5,
		preview_height = 4,
		commit_height = 6,
		discovery = { mode = "git", provider = "git", root = "/repo" },
		items = {
			{
				id = "git-working",
				kind = "target",
				label = "Working tree changes",
				description = "Tracked changes",
				badge = "git",
				target = { kind = "local_git", base = "HEAD", head = "WORKING" },
				summary_lines = { "1 file changed" },
			},
			{ id = "commit-range", kind = "commit_range", label = "Commit range", badge = "range" },
			{ id = "custom", kind = "custom", label = "Custom target", badge = "custom" },
		},
	}, overrides or {})
end

local function discovery_for_open()
	local state = picker_state()
	return vim.tbl_extend("force", state.discovery, { items = state.items })
end

local function callback_for(state, lhs)
	for _, map in ipairs(vim.api.nvim_buf_get_keymap(state.buf, "n")) do
		if map.lhs == lhs then
			return map.callback
		end
	end
	local normalized_lhs = lhs:lower()
	for _, map in ipairs(vim.api.nvim_buf_get_keymap(state.buf, "n")) do
		if map.lhs:lower() == normalized_lhs then
			return map.callback
		end
	end
	return nil
end

local function press(state, lhs)
	local callback = assert(callback_for(state, lhs), "missing picker keymap " .. lhs)
	callback()
end

describe("target picker rendering", function()
	local original_recent_commits
	local original_normalize_custom
	local original_normalize_github_pr
	local original_open_pull_requests

	before_each(function()
		original_recent_commits = discovery.recent_commits
		original_normalize_custom = discovery.normalize_custom
		original_normalize_github_pr = discovery.normalize_github_pr
		original_open_pull_requests = discovery.open_pull_requests
	end)

	after_each(function()
		rawset(discovery, "recent_commits", original_recent_commits)
		rawset(discovery, "normalize_custom", original_normalize_custom)
		rawset(discovery, "normalize_github_pr", original_normalize_github_pr)
		rawset(discovery, "open_pull_requests", original_open_pull_requests)
		picker.close_current()
	end)

	it("renders a fixed-height target-list mode", function()
		local lines = picker.render_lines(picker_state())

		assert.are.equal(18, #lines)
		assert.matches("j/k  move", lines[1])
		assert.are.equal("", lines[2])
		assert.matches("Working tree changes", table.concat(lines, "\n"))
		assert.is_nil(table.concat(lines, "\n"):match("%d+ targets"))
	end)

	it("renders a fixed-height filtered empty state", function()
		local lines = picker.render_lines(picker_state({ filter = "nope" }))

		assert.are.equal(18, #lines)
		assert.matches("No targets match", table.concat(lines, "\n"))
	end)

	it("renders custom input mode with provider-specific examples", function()
		local lines = picker.render_lines(picker_state({ mode = "custom", custom_input = "origin/main" }))
		local text = table.concat(lines, "\n")

		assert.are.equal(18, #lines)
		assert.matches("Input: origin/main", text)
		assert.matches("origin/main%.%.%.HEAD", text)
		assert.matches("three%-dot", text)
		assert.matches("two%-dot", text)
	end)

	it("renders commit range mode with base/head markers and validation text", function()
		local lines = picker.render_lines(picker_state({
			mode = "commit",
			commits = {
				{ short_id = "c3", description = "new", provider = "git" },
				{ short_id = "c2", description = "base", provider = "git" },
			},
			commit_selected = 1,
			base_index = 2,
			head_index = 1,
		}))
		local text = table.concat(lines, "\n")

		assert.are.equal(18, #lines)
		assert.matches("Commit range", text)
		assert.matches("B", text)
		assert.matches("H", text)
		assert.matches("Base: c2", text)
		assert.matches("Head: c3", text)
	end)

	it("renders validation errors without changing picker height", function()
		local lines = picker.render_lines(picker_state({
			mode = "commit",
			commits = {
				{ short_id = "c3", description = "new", provider = "git" },
				{ short_id = "c2", description = "base", provider = "git" },
			},
			commit_selected = 1,
			base_index = 1,
			head_index = 1,
			validation_error = "Base and head must be different commits.",
		}))
		local text = table.concat(lines, "\n")

		assert.are.equal(18, #lines)
		assert.matches("Base and head must be different", text)
	end)

	it("filters commit range rows", function()
		local lines = picker.render_lines(picker_state({
			mode = "commit",
			commit_filter = "alpha",
			commits = {
				{ short_id = "aaa", description = "alpha change", provider = "git" },
				{ short_id = "bbb", description = "bravo change", provider = "git" },
			},
			commit_selected = 1,
		}))
		local text = table.concat(lines, "\n")

		assert.are.equal(18, #lines)
		assert.matches("Filter: alpha", text)
		assert.matches("alpha change", text)
		assert.is_nil(text:match("bravo change"))
	end)

	it("opens with rounded native floating windows and highlighted badges/key hints", function()
		local state = assert(picker.open({
			discovery = discovery_for_open(),
			height = 18,
			width = 72,
		}))
		local config = vim.api.nvim_win_get_config(state.win)
		local rendered = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
		local highlights = vim.api.nvim_buf_get_extmarks(state.buf, picker.ns, 0, -1, { details = true })
		local saw_badge = false
		local saw_key = false

		for _, mark in ipairs(highlights) do
			local details = mark[4] or {}
			if details.hl_group == "UnifiedReviewPickerBadge" then
				saw_badge = true
			elseif details.hl_group == "UnifiedReviewPickerKey" then
				saw_key = true
			end
		end

		assert.is_not_nil(config.border)
		assert.are.equal("center", config.title_pos)
		assert.matches("j/k  move", rendered)
		assert.not_matches("Keys:", rendered)
		assert.not_matches("Tabs:", rendered)
		assert.is_nil(config.footer)
		assert.is_true(saw_badge, "expected badge highlight extmarks")
		assert.is_true(saw_key, "expected key hint highlight extmarks")
	end)

	it("moves, filters, clears, and cancels target-list mode with keymaps", function()
		local canceled = false
		local state = assert(picker.open({
			discovery = discovery_for_open(),
			height = 18,
			width = 72,
			on_cancel = function()
				canceled = true
			end,
		}))

		press(state, "j")
		assert.are.equal(2, state.selected)
		press(state, "/")
		press(state, "x")
		assert.are.equal("x", state.filter)
		assert.are.equal(1, state.selected)
		press(state, "<C-l>")
		assert.are.equal("", state.filter)
		press(state, "q")

		assert.is_true(canceled)
		assert.is_false(vim.api.nvim_win_is_valid(state.win))
	end)

	it("supports custom input editing, escape, and normalized selection", function()
		local selected
		rawset(discovery, "normalize_custom", function(input)
			return { kind = "local_git", base = input, head = "HEAD", range_kind = "three_dot" }, nil
		end)
		local state = assert(picker.open({
			discovery = discovery_for_open(),
			height = 18,
			width = 72,
			on_select = function(target)
				selected = target
			end,
		}))

		state.selected = 3
		press(state, "<CR>")
		assert.are.equal("custom", state.mode)
		press(state, "o")
		assert.are.equal("o", state.custom_input)
		press(state, "<BS>")
		assert.are.equal("", state.custom_input)
		press(state, "<Esc>")
		assert.are.equal("list", state.mode)

		state.selected = 3
		press(state, "<CR>")
		state.custom_input = "origin/main"
		press(state, "<CR>")

		assert.is_not_nil(selected)
		assert.are.equal("origin/main", selected.base)
	end)

	it("supports selecting an open GitHub PR from the target list", function()
		local selected
		rawset(discovery, "open_pull_requests", function()
			return {
				{
					number = 123,
					title = "Add review picker",
					base_name = "main",
					head_name = "feature",
					author = "octo",
					target = { kind = "github_pr", number = 123 },
				},
				{
					number = 124,
					title = "Other change",
					target = { kind = "github_pr", number = 124 },
				},
			},
				nil
		end)
		local disc = discovery_for_open()
		table.insert(
			disc.items,
			2,
			{ id = "github-pr-picker", kind = "github_pr_picker", label = "GitHub PR", badge = "pr" }
		)
		local state = assert(picker.open({
			discovery = disc,
			height = 18,
			width = 72,
			on_select = function(target)
				selected = target
			end,
		}))

		state.selected = 2
		press(state, "<CR>")
		assert.are.equal("pr", state.mode)
		press(state, "/")
		press(state, "p")
		assert.are.equal("p", state.pr_filter)
		press(state, "<C-l>")
		assert.are.equal("", state.pr_filter)
		press(state, "<CR>")

		assert.is_not_nil(selected)
		assert.are.equal("github_pr", selected.kind)
		assert.are.equal(123, selected.number)
	end)

	it("supports commit range keymaps and inline validation", function()
		local selected
		rawset(discovery, "recent_commits", function()
			return {
				{ provider = "git", oid = "c3", short_id = "c3", description = "new" },
				{ provider = "git", oid = "c2", short_id = "c2", description = "base" },
			},
				nil
		end)
		local state = assert(picker.open({
			discovery = discovery_for_open(),
			height = 18,
			width = 72,
			on_select = function(target)
				selected = target
			end,
		}))

		state.selected = 2
		press(state, "<CR>")
		assert.are.equal("commit", state.mode)
		assert.are.equal(2, state.base_index)
		assert.are.equal(1, state.head_index)
		press(state, "/")
		press(state, "n")
		assert.are.equal("n", state.commit_filter)
		press(state, "<C-l>")
		assert.are.equal("", state.commit_filter)
		press(state, "j")
		press(state, "h")
		assert.are.equal(2, state.head_index)
		press(state, "<CR>")
		assert.matches("different", state.validation_error)
		press(state, "k")
		press(state, "h")
		press(state, "<CR>")

		assert.is_not_nil(selected)
		assert.are.equal("c2", selected.base)
		assert.are.equal("c3", selected.head)
	end)

	it("selects a target with <CR>", function()
		local selected
		local state = assert(picker.open({
			discovery = discovery_for_open(),
			height = 18,
			width = 72,
			on_select = function(target)
				selected = target
			end,
		}))

		press(state, "<CR>")

		assert.is_not_nil(selected)
		assert.are.equal("HEAD", selected.base)
	end)

	it("lets j/k/q type into the filter after entering filter mode with /", function()
		local canceled = false
		local state = assert(picker.open({
			discovery = discovery_for_open(),
			height = 18,
			width = 72,
			on_cancel = function()
				canceled = true
			end,
		}))

		press(state, "/")
		assert.is_true(state.filtering)
		press(state, "j")
		press(state, "k")
		press(state, "q")
		assert.are.equal("jkq", state.filter)

		press(state, "<Esc>")
		assert.is_false(state.filtering)

		press(state, "q")
		assert.is_true(canceled)
		assert.is_false(vim.api.nvim_win_is_valid(state.win))
	end)

	it("ignores printable keys in non-filtering mode", function()
		local state = assert(picker.open({
			discovery = discovery_for_open(),
			height = 18,
			width = 72,
		}))

		press(state, "a")
		assert.are.equal("", state.filter)
		assert.is_false(state.filtering)

		press(state, "x")
		assert.are.equal("", state.filter)
		assert.is_false(state.filtering)
	end)

	it("lets b/h type into the commit filter in filter mode", function()
		rawset(discovery, "recent_commits", function()
			return {
				{ provider = "git", oid = "c3", short_id = "c3", description = "new" },
				{ provider = "git", oid = "c2", short_id = "c2", description = "base" },
			},
				nil
		end)
		local state = assert(picker.open({
			discovery = discovery_for_open(),
			height = 18,
			width = 72,
		}))

		state.selected = 2
		press(state, "<CR>")
		assert.are.equal("commit", state.mode)

		press(state, "/")
		assert.is_true(state.filtering)
		press(state, "b")
		press(state, "h")
		assert.are.equal("bh", state.commit_filter)

		press(state, "<Esc>")
		assert.is_false(state.filtering)

		press(state, "j")
		press(state, "b")
		assert.are.equal(2, state.base_index)
	end)
end)
