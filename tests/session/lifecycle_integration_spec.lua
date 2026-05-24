local config = require("unified_review.config")
local git_provider = require("unified_review.providers.diff.git_local")
local comment_provider = require("unified_review.providers.comments.local_store")
local session_store = require("unified_review.persist.session_store")
local selection = require("unified_review.session.selection")
local export = require("unified_review.export")
local git_repo = require("tests.helpers.git_repo")

local function setup_config()
	local state_dir = vim.fn.tempname()
	vim.fn.mkdir(state_dir, "p")
	config.setup({ local_git = { state_dir = state_dir } })
	return state_dir
end

--- Open a session directly via providers, bypassing CodeDiff UI.
--- Use a stable session_id derived from the repo root so persistence works
--- across commits (head changes but the review target is the same branch).
local function open_session(repo, opts)
	opts = opts or {}
	local session, err = git_provider.open({
		cwd = repo.root,
		base = repo.base,
		head = repo.head,
		range_kind = "two_dot",
	})
	assert(session, err and (err.message or err.stderr) or "failed to open")
	-- Use a stable session_id keyed on the base ref, so comments survive head changes.
	local base_key = session.target.base_oid or session.target.base or repo.base
	session.id = opts.session_id or ("review:" .. base_key)
	session.kind = "local_git"
	comment_provider.load(session)
	selection.initialize(session)
	return session
end

describe("session lifecycle integration", function()
	after_each(function()
		config.setup({})
		vim.cmd("silent! only")
	end)

	it("opens a session with multiple files and selects them", function()
		setup_config()
		local repo = git_repo.multi_file()

		local session = open_session(repo)

		assert.are.equal("local_git", session.kind)
		assert.are.equal(2, #session.files)
		assert.are.equal("src/main.lua", session.files[1].path)
		assert.are.equal("src/utils.lua", session.files[2].path)

		-- navigate files
		assert.are.equal("src/main.lua", selection.current_file(session).path)
		assert.are.equal("src/utils.lua", selection.next_file(session).path)
		assert.are.equal("src/main.lua", selection.previous_file(session).path)

		-- each file has hunks
		assert.is_true(#session.files[1].hunks > 0)
		assert.is_true(#session.files[2].hunks > 0)
	end)

	it("handles renamed and new files in a session", function()
		setup_config()
		local repo = git_repo.rename_and_new()

		local session = open_session(repo)

		assert.is_true(#session.files >= 3, "expected at least 3 files")
		local found_rename = false
		for _, f in ipairs(session.files) do
			if f.old_path and f.old_path ~= f.path then
				found_rename = true
				assert.are.equal("renamed", f.status)
			end
		end
		assert.is_true(found_rename, "should have a renamed file")
	end)

	it("persists comments and remaps anchors after file changes", function()
		setup_config()
		local repo = git_repo.changed_file()

		-- open, comment, persist, close
		local session = open_session(repo)
		assert(comment_provider.create_thread(session, {
			kind = "line",
			path = repo.path,
			side = "right",
			line = 2,
		}, "anchor note"))
		assert(comment_provider.create_thread(session, {
			kind = "line",
			path = repo.path,
			side = "right",
			line = 3,
		}, "another note"))
		session_store.write(session)

		-- modify the file: insert a line at the top
		local lines = git_repo.read(repo.root, repo.path)
		table.insert(lines, 1, "local new_first = 0")
		git_repo.write(repo.root, repo.path, lines)
		git_repo.commit(repo.root, "insert top line")

		-- reopen with new HEAD, using the same stable session_id
		local new_head =
			vim.trim(vim.system({ "git", "-C", repo.root, "rev-parse", "HEAD" }, { text = true }):wait().stdout)
		local reopened = open_session({
			root = repo.root,
			base = repo.base,
			head = new_head,
			path = repo.path,
		}, { session_id = session.id })

		local threads = comment_provider.list_threads(reopened, repo.path)
		assert.are.equal(2, #threads)

		-- anchors should remap (old lines 2,3 → new lines 3,4 after insert)
		for _, thread in ipairs(threads) do
			if thread.target.line then
				assert.is_true(
					thread.target.line > 1,
					"expected remapped line > 1, got " .. tostring(thread.target.line)
				)
			end
		end
	end)

	it("marks anchors stale when the target line disappears", function()
		setup_config()
		local repo = git_repo.changed_file()

		local session = open_session(repo)
		assert(comment_provider.create_thread(session, {
			kind = "line",
			path = repo.path,
			side = "right",
			line = 2,
		}, "will go stale"))
		session_store.write(session)

		-- totally rewrite the file
		git_repo.write(repo.root, repo.path, {
			"completely new content",
			"no resemblance to original",
		})
		git_repo.commit(repo.root, "total rewrite")

		local new_head =
			vim.trim(vim.system({ "git", "-C", repo.root, "rev-parse", "HEAD" }, { text = true }):wait().stdout)
		local reopened = open_session({
			root = repo.root,
			base = repo.base,
			head = new_head,
			path = repo.path,
		}, { session_id = session.id })

		local threads = comment_provider.list_threads(reopened, repo.path)
		assert.are.equal(1, #threads)
		assert.are.equal("stale", threads[1].state)
		assert.is_true(threads[1].is_outdated)
	end)

	it("exports correctly formatted markdown and minimal formats", function()
		setup_config()
		local repo = git_repo.changed_file()

		local session = open_session(repo)
		assert(comment_provider.create_thread(session, { kind = "file", path = repo.path }, "export test body"))

		local threads = comment_provider.list_threads(session)
		assert.are.equal(1, #threads)

		-- markdown format
		local md = export.format(threads, { format = "markdown" })
		assert.matches("# Code Review", md)
		assert.matches("a%.lua", md)
		assert.matches("export test body", md)

		-- minimal format
		local minimal = export.format(threads, { format = "minimal" })
		assert.matches("a%.lua: export test body", minimal)

		-- save to file
		local path = vim.fn.tempname()
		export.save(path, threads, { format = "minimal" })
		local saved = table.concat(vim.fn.readfile(path), "\n")
		assert.are.equal("a.lua: export test body", saved)
	end)

	it("clears all comments and verifies empty session", function()
		setup_config()
		local repo = git_repo.changed_file()

		local session = open_session(repo)
		assert(comment_provider.create_thread(session, { kind = "file", path = repo.path }, "one"))
		assert(
			comment_provider.create_thread(
				session,
				{ kind = "line", path = repo.path, side = "right", line = 1 },
				"two"
			)
		)
		local thread = comment_provider.list_threads(session)[1]
		assert(comment_provider.reply(session, thread.id, "reply"))

		assert.are.equal(2, #comment_provider.list_threads(session))

		assert(comment_provider.clear(session))
		assert.are.equal(0, #comment_provider.list_threads(session))
		assert.are.equal(0, #comment_provider.list_threads(session, repo.path))

		-- export of empty session produces empty string
		local md = export.format(comment_provider.list_threads(session) or {}, { format = "markdown" })
		assert.are.equal("", md)
	end)

	it("handles reopen with no pre-existing comments gracefully", function()
		setup_config()
		local repo = git_repo.changed_file()

		local session = open_session(repo)
		assert.are.equal(0, #comment_provider.list_threads(session))
		session_store.write(session)

		local reopened = open_session(repo)
		assert.are.equal(0, #comment_provider.list_threads(reopened))
		assert.are.equal(1, #reopened.files)
	end)
end)
