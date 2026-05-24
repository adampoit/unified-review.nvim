local config = require("unified_review.config")
local manager = require("unified_review.session.manager")
local state = require("unified_review.session.state")
local target_discovery = require("unified_review.session.target_discovery")
local session_store = require("unified_review.persist.session_store")

describe("session manager", function()
	after_each(function()
		config.setup({})
		state.clear_active()
	end)

	it("tracks and closes active sessions", function()
		state.set_active({ files = {}, ui = {} })
		assert.is_not_nil(manager.active())
		assert.is_true(manager.close())
		assert.is_nil(manager.active())
	end)

	it("reports no-op close without an active session", function()
		assert.is_false(manager.close())
	end)

	local function active_session()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		local session = {
			id = "session-1",
			target = { root = root },
			files = { { path = "a.lua", hunks = {} } },
			selection = { file_index = 1 },
			threads = {},
		}
		state.set_active(session)
		return session
	end

	it("opens the normalized current target chosen by discovery", function()
		local original_current_target = target_discovery.current_target
		local original_open_target = manager.open_target
		local opened
		rawset(target_discovery, "current_target", function()
			return { id = "git-origin/main", target = { id = "current", head = "WORKING" } }, nil
		end)
		rawset(manager, "open_target", function(target)
			opened = target
			return { id = "session" }, nil
		end)

		manager.open_current_change({})

		rawset(target_discovery, "current_target", original_current_target)
		rawset(manager, "open_target", original_open_target)
		assert.are.equal("current", opened and opened.id)
	end)

	it("creates comments and replies through the active session", function()
		active_session()

		local thread = assert(manager.create_comment("note", { kind = "file", path = "a.lua" }))
		assert.are.equal(1, #manager.list_threads("a.lua"))
		local reply = assert(manager.reply(thread.id, "reply"))
		assert.are.equal(thread.id, reply.thread_id)
		assert.are.equal(2, #thread.comments)
	end)

	it("resolves and reopens threads through the active session", function()
		active_session()
		local thread = assert(manager.create_comment("note", { kind = "file", path = "a.lua" }))

		assert.are.equal("resolved", assert(manager.resolve_thread(thread.id)).state)
		assert.are.equal("open", assert(manager.reopen_thread(thread.id)).state)
	end)

	it("auto-copies review text when configured", function()
		active_session()
		local clipboard = ""
		vim.g.clipboard = {
			name = "test-clipboard",
			copy = {
				["+"] = function(lines)
					clipboard = table.concat(lines, "\n")
				end,
				["*"] = function(lines)
					clipboard = table.concat(lines, "\n")
				end,
			},
			paste = {
				["+"] = function()
					return vim.split(clipboard, "\n", { plain = true }), "v"
				end,
				["*"] = function()
					return vim.split(clipboard, "\n", { plain = true }), "v"
				end,
			},
		}
		config.setup({ local_git = { auto_copy_on_add = true } })

		manager.create_comment("note", { kind = "file", path = "a.lua" })

		assert.matches("note", clipboard)
	end)

	it("toggles thread export markers", function()
		active_session()
		local thread = assert(manager.create_comment("note", { kind = "file", path = "a.lua" }))

		assert.is_true(thread.metadata.export)
		assert.is_false(assert(manager.toggle_thread_export(thread.id)).metadata.export)
		local stored = assert(session_store.read(manager.active().target.root, manager.active().id))
		assert.is_false(stored.threads[1].metadata.export)
		assert.is_true(assert(manager.toggle_thread_export(thread.id)).metadata.export)
	end)

	it("clears comments through the active session", function()
		active_session()
		assert(manager.create_comment("note", { kind = "file", path = "a.lua" }))
		assert.are.equal(1, #manager.list_threads())

		assert(manager.clear_comments())
		assert.are.equal(0, #manager.list_threads())
	end)

	it("returns an error instead of throwing when no comment target is available", function()
		state.set_active({ files = {}, selection = {}, threads = {}, ui = {} })

		local thread, err = manager.create_comment("note")

		assert.is_nil(thread)
		assert.are.equal("No comment target at cursor", err and err.message)
	end)
end)
