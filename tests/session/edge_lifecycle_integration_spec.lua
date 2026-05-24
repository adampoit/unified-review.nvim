local commands = require("unified_review.commands")
local config = require("unified_review.config")
local manager = require("unified_review.session.manager")
local state = require("unified_review.session.state")
local git_repo = require("tests.helpers.git_repo")

local function setup_config()
	local state_dir = vim.fn.tempname()
	vim.fn.mkdir(state_dir, "p")
	config.setup({ local_git = { state_dir = state_dir } })
	commands.setup()
	return state_dir
end

local function open_repo(repo)
	return assert(manager.open_local({ cwd = repo.root, base = repo.base, head = repo.head, range_kind = "two_dot" }))
end

local function create_deleted_file_repo()
	local root = git_repo.create()
	git_repo.write(root, "gone.txt", { "first", "second", "third" })
	local base = git_repo.commit(root, "base")
	vim.fn.delete(root .. "/gone.txt")
	local head = git_repo.commit(root, "delete file")
	return { root = root, base = base, head = head, path = "gone.txt" }
end

local function create_binary_file_repo()
	local root = git_repo.create()
	git_repo.write(root, ".gitattributes", { "*.bin binary" })
	vim.system({ "sh", "-c", "printf '\\000\\001before' > image.bin" }, { cwd = root }):wait()
	local base = git_repo.commit(root, "base")
	vim.system({ "sh", "-c", "printf '\\000\\001after' > image.bin" }, { cwd = root }):wait()
	local head = git_repo.commit(root, "binary change")
	return { root = root, base = base, head = head, path = "image.bin" }
end

describe("edge lifecycle integration", function()
	local original_notify
	local notifications

	before_each(function()
		setup_config()
		original_notify = vim.notify
		notifications = {}
		rawset(vim, "notify", function(message, level, opts)
			table.insert(notifications, { message = message, level = level, opts = opts })
		end)
	end)

	after_each(function()
		rawset(vim, "notify", original_notify)
		pcall(manager.close)
		state.clear_active()
		config.setup({})
		vim.cmd("silent! only")
	end)

	it("opens and closes an empty diff session", function()
		local repo = git_repo.changed_file()
		local session =
			assert(manager.open_local({ cwd = repo.root, base = repo.head, head = repo.head, range_kind = "two_dot" }))

		assert.are.equal(0, #session.files)
		assert.is_not_nil(manager.active())
		assert.is_true(manager.close())
		assert.is_nil(manager.active())
	end)

	it("reports invalid command ranges without leaving an active session", function()
		local repo = git_repo.changed_file()
		vim.cmd.lcd(vim.fn.fnameescape(repo.root))

		vim.cmd("UnifiedReview local does-not-exist..HEAD")

		assert.is_nil(manager.active())
		assert.is_true(vim.tbl_contains(
			vim.tbl_map(function(entry)
				return entry.level
			end, notifications),
			vim.log.levels.ERROR
		))
	end)

	it("keeps deleted-file comments across close and reopen", function()
		local repo = create_deleted_file_repo()
		local session = open_repo(repo)
		local deleted_file = assert(session.files[1])
		assert.are.equal("deleted", deleted_file.status)

		local thread = assert(manager.create_comment("deleted file note", { kind = "file", path = repo.path }))
		local session_id = session.id
		assert.are.equal("file", thread.target.kind)
		manager.close()

		local reopened = open_repo(repo)
		assert.are.equal(session_id, reopened.id)
		local threads = assert(manager.list_threads(repo.path))
		local reopened_thread = assert(threads[1])
		local reopened_comment = assert(reopened_thread.comments[1])
		assert.are.equal(1, #threads)
		assert.are.equal("deleted file note", reopened_comment.body)
		assert.are.equal(repo.path, reopened_thread.target.path)
	end)

	it("supports file-level comments on binary diffs and persists them", function()
		local repo = create_binary_file_repo()
		local session = open_repo(repo)
		local binary_file = assert(session.files[1])
		assert.are.equal("binary", binary_file.status)
		assert.are.equal(0, #binary_file.hunks)

		assert(manager.create_comment("binary file note", { kind = "file", path = repo.path }))
		manager.close()

		open_repo(repo)
		local threads = assert(manager.list_threads(repo.path))
		local binary_thread = assert(threads[1])
		local binary_comment = assert(binary_thread.comments[1])
		assert.are.equal(1, #threads)
		assert.are.equal("file", binary_thread.target.kind)
		assert.are.equal("binary file note", binary_comment.body)
	end)

	it("runs a command-driven local review happy path", function()
		local repo = git_repo.changed_file()
		vim.cmd.lcd(vim.fn.fnameescape(repo.root))
		vim.cmd("UnifiedReview local " .. repo.base .. ".." .. repo.head)
		assert.is_not_nil(manager.active())

		vim.cmd("UnifiedReview comment")
		local comment_buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_set_lines(comment_buf, 0, -1, false, { "command note" })
		vim.cmd.write()
		local threads = assert(manager.list_threads(repo.path))
		local command_thread = assert(threads[1])
		assert.are.equal(1, #threads)
		vim.cmd("UnifiedReview reply " .. command_thread.id)
		local reply_buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_set_lines(reply_buf, 0, -1, false, { "command reply" })
		vim.cmd.write()
		vim.cmd("UnifiedReview resolve-thread " .. command_thread.id)
		vim.cmd("UnifiedReview reopen-thread " .. command_thread.id)

		local save_path = vim.fn.tempname() .. ".md"
		require("unified_review.export").save(save_path, manager.list_threads() or {}, {
			format = "markdown",
			session = manager.active(),
		})
		local saved = table.concat(vim.fn.readfile(save_path), "\n")
		assert.matches("command note", saved)
		assert.matches("command reply", saved)

		vim.cmd("UnifiedReview close")
		assert.is_nil(manager.active())
	end)

	it("survives repeated open and close cycles", function()
		local repo = git_repo.changed_file()
		for _ = 1, 3 do
			open_repo(repo)
			assert.is_not_nil(manager.active())
			assert.is_true(manager.close())
			assert.is_nil(manager.active())
		end
	end)
end)
