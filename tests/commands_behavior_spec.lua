local commands = require("unified_review.commands")
local manager = require("unified_review.session.manager")
local selection = require("unified_review.session.selection")
local comment_editor = require("unified_review.ui.comment_editor")
local state = require("unified_review.session.state")
local config = require("unified_review.config")

describe("command behavior", function()
	local original_open_local
	local original_pick_review_target
	local original_open_current_change
	local original_open_pr
	local original_close
	local original_toggle_thread_export
	local original_publish_drafts
	local original_resolve_thread
	local original_reopen_thread
	local original_edit_draft
	local original_delete_draft
	local original_comment_editor_open
	local original_notify
	local original_ui_select
	local original_current_thread_candidates
	local notifications

	before_each(function()
		commands.setup()
		original_open_local = manager.open_local
		original_pick_review_target = manager.pick_review_target
		original_open_current_change = manager.open_current_change
		original_open_pr = manager.open_pr
		original_close = manager.close
		original_toggle_thread_export = manager.toggle_thread_export
		original_publish_drafts = manager.publish_drafts
		original_resolve_thread = manager.resolve_thread
		original_reopen_thread = manager.reopen_thread
		original_edit_draft = manager.edit_draft
		original_delete_draft = manager.delete_draft
		original_comment_editor_open = comment_editor.open
		original_notify = vim.notify
		original_ui_select = vim.ui.select
		original_current_thread_candidates = selection.current_thread_candidates
		notifications = {}
		rawset(vim, "notify", function(message, level, opts)
			table.insert(notifications, { message = message, level = level, opts = opts })
		end)
	end)

	after_each(function()
		rawset(manager, "open_local", original_open_local)
		rawset(manager, "pick_review_target", original_pick_review_target)
		rawset(manager, "open_current_change", original_open_current_change)
		rawset(manager, "open_pr", original_open_pr)
		rawset(manager, "close", original_close)
		rawset(manager, "toggle_thread_export", original_toggle_thread_export)
		rawset(manager, "publish_drafts", original_publish_drafts)
		rawset(manager, "resolve_thread", original_resolve_thread)
		rawset(manager, "reopen_thread", original_reopen_thread)
		rawset(manager, "edit_draft", original_edit_draft)
		rawset(manager, "delete_draft", original_delete_draft)
		rawset(comment_editor, "open", original_comment_editor_open)
		rawset(vim, "notify", original_notify)
		rawset(vim.ui, "select", original_ui_select)
		rawset(selection, "current_thread_candidates", original_current_thread_candidates)
		state.clear_active()
		config.setup({})
	end)

	it("UnifiedReview local parses two-dot ranges before opening a local session", function()
		local opened
		rawset(manager, "open_local", function(target)
			opened = target
			return { id = "session" }, nil
		end)

		vim.cmd("UnifiedReview local main..HEAD")

		assert.are.equal("main", opened.base)
		assert.are.equal("HEAD", opened.head)
		assert.are.equal("two_dot", opened.range_kind)
	end)

	it("UnifiedReview without args opens the target picker", function()
		local picked = false
		rawset(manager, "pick_review_target", function()
			picked = true
			return { id = "picker" }, nil
		end)

		vim.cmd("UnifiedReview")

		assert.is_true(picked)
	end)

	it("UnifiedReview local dispatches an explicit local range", function()
		local opened
		rawset(manager, "open_local", function(target)
			opened = target
			return { id = "session" }, nil
		end)

		vim.cmd("UnifiedReview local main HEAD")

		assert.are.equal("main", opened.base)
		assert.are.equal("HEAD", opened.head)
		assert.are.equal("three_dot", opened.range_kind)
	end)

	it("UnifiedReview current dispatches current-change discovery", function()
		local opened = false
		rawset(manager, "open_current_change", function()
			opened = true
			return { id = "session" }, nil
		end)

		vim.cmd("UnifiedReview current")

		assert.is_true(opened)
	end)

	it("UnifiedReview direct range args are treated as a local target", function()
		local opened
		rawset(manager, "open_local", function(target)
			opened = target
			return { id = "session" }, nil
		end)

		vim.cmd("UnifiedReview main..HEAD")

		assert.are.equal("main", opened.base)
		assert.are.equal("HEAD", opened.head)
		assert.are.equal("two_dot", opened.range_kind)
	end)

	it("UnifiedReview pr dispatches explicit PR opening", function()
		local pr
		rawset(manager, "open_pr", function(value)
			pr = value
			return { id = "session" }, nil
		end)

		vim.cmd("UnifiedReview pr 123")

		assert.are.equal("123", pr)
	end)

	it("UnifiedReview pr without args opens the PR from branch context", function()
		local called = false
		rawset(manager, "open_pr", function(value)
			called = true
			assert.is_nil(value)
			return { id = "session" }, nil
		end)

		vim.cmd("UnifiedReview pr")

		assert.is_true(called)
	end)

	it("UnifiedReview close closes the active session", function()
		state.set_active({ files = {}, ui = {} })

		vim.cmd("UnifiedReview close")

		assert.is_nil(manager.active())
	end)

	it("UnifiedReview comment without an active session reports a no-op", function()
		vim.cmd("UnifiedReview comment")

		assert.are.equal("No active review session", notifications[1].message)
		assert.are.equal(vim.log.levels.INFO, notifications[1].level)
	end)

	it("UnifiedReview summary opens the consolidated review summary surface", function()
		state.set_active({ files = {}, threads = {}, ui = {} })

		vim.cmd("UnifiedReview summary")

		assert.matches("unified%-review://summary", vim.api.nvim_buf_get_name(0))
		local maps = vim.api.nvim_buf_get_keymap(0, "n")
		local by_lhs = {}
		for _, map in ipairs(maps) do
			by_lhs[map.lhs] = true
		end
		assert.is_true(by_lhs.y)
		assert.is_true(by_lhs.w)
		assert.is_nil(by_lhs.e)
	end)

	it("UnifiedReview toggle-export dispatches to the manager", function()
		local toggled
		rawset(manager, "toggle_thread_export", function(thread_id)
			toggled = thread_id
			return { id = thread_id }, nil
		end)

		vim.cmd("UnifiedReview toggle-export thread-1")

		assert.are.equal("thread-1", toggled)
	end)

	it("UnifiedReview toggle-export toggles the only thread at the cursor", function()
		state.set_active({ id = "s", files = {}, threads = {}, ui = {} })
		rawset(selection, "current_thread_candidates", function()
			return { { id = "thread-solo" } }
		end)
		local toggled
		rawset(manager, "toggle_thread_export", function(thread_id)
			toggled = thread_id
			return { id = thread_id }, nil
		end)
		local select_called = false
		rawset(vim.ui, "select", function(_, _, on_choice)
			select_called = true
			if on_choice then
				on_choice({ id = "thread-solo" })
			end
		end)

		vim.cmd("UnifiedReview toggle-export")

		assert.are.equal("thread-solo", toggled)
		assert.is_false(select_called)
	end)

	it("UnifiedReview toggle-export disambiguates overlapping comments at the cursor", function()
		local candidates = {
			{ id = "thread-range", target = { kind = "range", path = "a.lua", start_line = 10, line = 15 } },
			{ id = "thread-single", target = { kind = "line", path = "a.lua", line = 12 } },
		}
		state.set_active({ id = "s", files = {}, threads = {}, ui = {} })
		rawset(selection, "current_thread_candidates", function()
			return candidates
		end)
		local toggled
		rawset(manager, "toggle_thread_export", function(thread_id)
			toggled = thread_id
			return { id = thread_id }, nil
		end)
		local select_prompt
		rawset(vim.ui, "select", function(items, opts, on_choice)
			select_prompt = opts.prompt
			assert.are.equal(2, #items)
			-- The user picks the nested single-line comment.
			on_choice(items[2])
		end)

		vim.cmd("UnifiedReview toggle-export")

		assert.are.equal("thread-single", toggled)
		assert.is_true(select_prompt ~= nil and select_prompt:match("which comment") ~= nil)
	end)

	it("UnifiedReview resolve-thread disambiguates overlapping comments at the cursor", function()
		local candidates = {
			{ id = "thread-range" },
			{ id = "thread-single" },
		}
		state.set_active({ id = "s", files = {}, threads = {}, ui = {} })
		rawset(selection, "current_thread_candidates", function()
			return candidates
		end)
		local resolved
		rawset(manager, "resolve_thread", function(thread_id)
			resolved = thread_id
			return { id = thread_id }, nil
		end)
		rawset(vim.ui, "select", function(items, _, on_choice)
			on_choice(items[1])
		end)

		vim.cmd("UnifiedReview resolve-thread")

		assert.are.equal("thread-range", resolved)
	end)

	it("UnifiedReview reopen-thread toggles the only thread under the cursor", function()
		state.set_active({ id = "s", files = {}, threads = {}, ui = {} })
		rawset(selection, "current_thread_candidates", function()
			return { { id = "thread-solo" } }
		end)
		local reopened
		rawset(manager, "reopen_thread", function(thread_id)
			reopened = thread_id
			return { id = thread_id }, nil
		end)

		vim.cmd("UnifiedReview reopen-thread")

		assert.are.equal("thread-solo", reopened)
	end)

	it("UnifiedReview reply disambiguates overlapping comments and opens the editor for the choice", function()
		local candidates = {
			{ id = "thread-range" },
			{ id = "thread-single" },
		}
		state.set_active({ id = "s", files = {}, threads = {}, ui = {} })
		rawset(selection, "current_thread_candidates", function()
			return candidates
		end)
		local opened
		rawset(comment_editor, "open", function(opts)
			opened = opts
		end)
		rawset(vim.ui, "select", function(items, _, on_choice)
			on_choice(items[2])
		end)

		vim.cmd("UnifiedReview reply")

		assert.are.same({ thread_id = "thread-single" }, opened)
	end)

	it("UnifiedReview delete-draft disambiguates overlapping comments at the cursor", function()
		state.set_active({ id = "s", files = {}, threads = {}, ui = {} })
		rawset(selection, "current_thread_candidates", function()
			return {
				{ id = "thread-range", comments = { { id = "comment-range" } } },
				{ id = "thread-single", comments = { { id = "comment-single" } } },
			}
		end)
		local deleted
		rawset(manager, "delete_draft", function(comment_id)
			deleted = comment_id
			return true, nil
		end)
		rawset(vim.ui, "select", function(items, _, on_choice)
			on_choice(items[2])
		end)

		vim.cmd("UnifiedReview delete-draft")

		assert.are.equal("comment-single", deleted)
	end)

	it("UnifiedReview publish-drafts dispatches to the manager", function()
		local published
		rawset(manager, "publish_drafts", function(pr_ref)
			published = pr_ref
			return { successes = {}, failures = {} }, nil
		end)

		vim.cmd("UnifiedReview publish-drafts 123")

		assert.are.equal("123", published)
	end)

	it("UnifiedReview save writes active review comments to a path", function()
		local path = vim.fn.tempname()
		state.set_active({
			target = { root = vim.fn.getcwd() },
			files = {},
			ui = {},
			threads = {
				{
					id = "thread-1",
					state = "open",
					metadata = { export = true },
					target = { kind = "line", path = "a.lua", side = "right", line = 10 },
					comments = {
						{ id = "comment-1", author = "Ada", body = "Please simplify this." },
					},
				},
			},
		})

		vim.cmd("UnifiedReview save " .. vim.fn.fnameescape(path) .. " minimal")

		assert.are.equal("a.lua:L10: Please simplify this.", table.concat(vim.fn.readfile(path), "\n"))
	end)
end)
