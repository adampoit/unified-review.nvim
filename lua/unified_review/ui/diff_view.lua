local config = require("unified_review.config")
local selection = require("unified_review.session.selection")
local signs = require("unified_review.ui.signs")
local debug = require("unified_review.util.debug")

local M = {}

local function detect_filetype(path)
	return vim.filetype.match({ filename = path }) or ""
end

local function codediff_modules()
	local ok_view, view = pcall(require, "codediff.ui.view")
	local ok_lifecycle, lifecycle = pcall(require, "codediff.ui.lifecycle")
	if not ok_view or not ok_lifecycle then
		return nil, nil
	end
	return view, lifecycle
end

local function status_char(status)
	return ({
		added = "A",
		modified = "M",
		deleted = "D",
		renamed = "R",
		copied = "C",
		type_changed = "T",
		binary = "M",
	})[status] or "M"
end

local function normalize_status(status)
	return ({
		A = "added",
		M = "modified",
		D = "deleted",
		R = "renamed",
		C = "copied",
		T = "type_changed",
		["??"] = "added",
	})[status] or status or "modified"
end

local function explorer_data(session)
	local unstaged = {}
	for _, file in ipairs(session.files or {}) do
		table.insert(unstaged, {
			path = file.path,
			old_path = file.old_path,
			status = status_char(file.status),
		})
	end
	return { status_result = { unstaged = unstaged, staged = {}, conflicts = {} } }
end

local function render_root(target)
	target = target or {}
	return target.worktree_root or target.root or target.git_root
end

local function working_root(target)
	target = target or {}
	return target.worktree_root or target.root or target.git_root
end

local function working_path(target, path)
	if not path or path == "" or path:match("^/") then
		return path
	end
	local root = working_root(target)
	if not root or root == "" then
		return path
	end
	return (root:gsub("[/\\]$", "")) .. "/" .. path
end

local function is_jj_current_head(target)
	return target and target.kind == "jj" and target.git_root and (target.head_revset == "@" or target.head == "@")
end

local function modified_revision(target)
	target = target or {}
	if target.head_oid == "WORKING" or target.render_head_oid == "WORKING" or is_jj_current_head(target) then
		return "WORKING"
	end
	if target.head_oid and target.head_oid ~= "WORKING" then
		return target.head_oid
	end
	if target.head and target.head ~= "WORKING" then
		return target.head
	end
	return "WORKING"
end

local function normalize_path(session, path)
	if not path or path == "" then
		return path
	end
	path = tostring(path):gsub("\\", "/"):gsub("^%./", "")
	if not path:match("^/") then
		return path
	end

	local root = session and session.target and working_root(session.target)
	if not root or root == "" then
		return path
	end
	local real_root = vim.loop.fs_realpath(root) or vim.fn.fnamemodify(root, ":p")
	local real_path = vim.loop.fs_realpath(path) or vim.fn.fnamemodify(path, ":p")
	real_root = tostring(real_root):gsub("\\", "/"):gsub("/$", "")
	real_path = tostring(real_path):gsub("\\", "/")
	local prefix = real_root .. "/"
	if real_path:sub(1, #prefix) == prefix then
		return real_path:sub(#prefix + 1)
	end
	return path
end

local function find_file_by_path(session, path)
	path = normalize_path(session, path)
	for index, file in ipairs(session.files or {}) do
		local file_path = normalize_path(session, file.path)
		local old_path = normalize_path(session, file.old_path)
		if file_path == path or old_path == path then
			return file, index
		end
	end
	return nil, nil
end

local function ensure_file(session, file_data, opts)
	if not file_data or not file_data.path or file_data.path == "" then
		return nil
	end
	opts = opts or {}
	local path = normalize_path(session, file_data.path)
	local existing, existing_index = find_file_by_path(session, path)
	if existing then
		if opts.select ~= false then
			selection.select_file(session, existing_index)
		end
		return existing
	end
	session.files = session.files or {}
	local file = {
		path = path,
		old_path = normalize_path(session, file_data.old_path),
		status = normalize_status(file_data.status),
		additions = 0,
		deletions = 0,
		hunks = {},
	}
	table.insert(session.files, file)
	if opts.select ~= false then
		selection.select_file(session, #session.files)
	end
	return file
end

local function current_codediff_file(session)
	if not session.ui or not session.ui.codediff_tab then
		return selection.current_file(session)
	end
	local _, lifecycle = codediff_modules()
	if not lifecycle then
		return selection.current_file(session)
	end
	local _, modified_path = lifecycle.get_paths(session.ui.codediff_tab)
	return ensure_file(session, { path = modified_path, status = "M" }) or selection.current_file(session)
end

local function attach_review_keymaps(session)
	local km = config.options.ui.keymaps
	if not km.enabled then
		return
	end
	local function set(buf, mode, lhs, rhs, opts_override)
		if not lhs or not buf or not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { buffer = buf, silent = true }, opts_override or {}))
	end
	local function add_buffer(buffers, seen, buf)
		if buf and vim.api.nvim_buf_is_valid(buf) and not seen[buf] then
			seen[buf] = true
			table.insert(buffers, buf)
		end
	end
	local buffers = {}
	local seen = {}
	add_buffer(buffers, seen, session.ui.left_buffer)
	add_buffer(buffers, seen, session.ui.right_buffer)
	if session.ui.left_window and vim.api.nvim_win_is_valid(session.ui.left_window) then
		add_buffer(buffers, seen, vim.api.nvim_win_get_buf(session.ui.left_window))
	end
	if session.ui.right_window and vim.api.nvim_win_is_valid(session.ui.right_window) then
		add_buffer(buffers, seen, vim.api.nvim_win_get_buf(session.ui.right_window))
	end
	add_buffer(buffers, seen, session.ui.files_buffer)

	local codediff_session = session.ui.codediff_session
	if not codediff_session and session.ui.codediff_tab then
		local _, lifecycle = codediff_modules()
		codediff_session = lifecycle and lifecycle.get_session(session.ui.codediff_tab)
	end
	local explorer = codediff_session and codediff_session.explorer
	if explorer then
		add_buffer(buffers, seen, explorer.bufnr)
	end
	add_buffer(buffers, seen, codediff_session and codediff_session.result_bufnr)

	for _, buf in ipairs(buffers) do
		set(buf, "n", km.comment, "<cmd>UnifiedReview comment<cr>")
		set(buf, "n", km.reply, "<cmd>UnifiedReview reply<cr>")
		set(buf, "n", km.threads, "<cmd>UnifiedReview threads<cr>")
		set(buf, "n", km.summary or km.submit, "<cmd>UnifiedReview summary<cr>")
		set(buf, "n", km.toggle_export, "<cmd>UnifiedReview toggle-export<cr>")
	end
	debug.event("diff.keymaps.attach", {
		session = session and session.id,
		buffers = buffers,
		codediff_tab = session and session.ui and session.ui.codediff_tab,
	})

	for _, buf in ipairs({ session.ui.left_buffer, session.ui.right_buffer }) do
		set(buf, "x", km.comment, function()
			local comment_editor = require("unified_review.ui.comment_editor")
			local side = buf == session.ui.left_buffer and "left" or "right"
			comment_editor.open({ target = selection.visual_target(session, side) })
		end)
		-- Toggle fold context: fold unchanged lines within diff hunks
		set(buf, "n", "zf", function()
			if vim.wo.foldmethod == "diff" then
				vim.wo.foldmethod = "manual"
				vim.wo.foldenable = false
			else
				vim.wo.foldmethod = "diff"
				vim.wo.foldenable = true
				vim.wo.foldlevel = 1
			end
		end)
	end
end

local function in_blocking_review_ui(session)
	if session and (session._comment_editor_open or session._review_modal_open) then
		return true
	end
	local name = vim.api.nvim_buf_get_name(0)
	return name:match("^unified%-review://comment/") ~= nil
end

local function window_buffer(win)
	if win and vim.api.nvim_win_is_valid(win) then
		return vim.api.nvim_win_get_buf(win)
	end
	return nil
end

local function sync_from_codediff(session, tabpage, result)
	if in_blocking_review_ui(session) then
		return
	end
	local _, lifecycle = codediff_modules()
	if not lifecycle then
		return
	end
	result = result or {}
	local left_buf, right_buf = lifecycle.get_buffers(tabpage)
	local left_win, right_win = lifecycle.get_windows(tabpage)
	local codediff_session = lifecycle.get_session(tabpage)
	local ui_left_win = left_win or result.original_win
	local ui_right_win = right_win or result.modified_win
	local win_left_buf = window_buffer(ui_left_win)
	local win_right_buf = window_buffer(ui_right_win)

	session.ui = session.ui or {}
	session.ui.tab = tabpage
	session.ui.codediff_tab = tabpage
	session.ui.left_buffer = win_left_buf or left_buf or result.original_buf
	session.ui.right_buffer = win_right_buf or right_buf or result.modified_buf
	session.ui.left_window = ui_left_win
	session.ui.right_window = ui_right_win
	if win_left_buf ~= left_buf or win_right_buf ~= right_buf then
		debug.event("diff.sync.window_buffers", {
			session = session.id,
			lifecycle_left_buffer = left_buf,
			lifecycle_right_buffer = right_buf,
			window_left_buffer = win_left_buf,
			window_right_buffer = win_right_buf,
		})
	end
	session.ui.buffers = { session.ui.left_buffer, session.ui.right_buffer }
	session.ui.windows = { session.ui.left_window, session.ui.right_window }
	session.ui.codediff_session = codediff_session

	current_codediff_file(session)
	local current_file = selection.current_file(session)
	if session.viewed_files and current_file and current_file.path then
		session.viewed_files[current_file.path] = true
	end
	pcall(require("unified_review.integrations.codediff_explorer").refresh, tabpage)
	if session.editable == false then
		for _, buf in ipairs({ session.ui.left_buffer, session.ui.right_buffer }) do
			if buf and vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].modifiable = false
				vim.bo[buf].readonly = true
			end
		end
	end
	attach_review_keymaps(session)
	signs.place(session)
	-- Place inline comments by default (can be toggled off)
	if session._inline_visible ~= false then
		require("unified_review.ui.inline").place(session)
	end

	-- Update tab label.
	local status = require("unified_review.ui.status")
	status.set_tab_label(tabpage, session)
end

local function schedule_sync(session, delay)
	local function run()
		if in_blocking_review_ui(session) then
			return
		end
		if session.ui and session.ui.codediff_tab and vim.api.nvim_tabpage_is_valid(session.ui.codediff_tab) then
			sync_from_codediff(session, session.ui.codediff_tab, {})
		end
	end
	if delay and delay > 0 then
		vim.defer_fn(run, delay)
		return
	end
	local ok = pcall(vim.api.nvim_create_autocmd, "SafeState", {
		once = true,
		callback = run,
	})
	if not ok then
		vim.schedule(run)
	end
end

local function attach_file_select_autocmd(session)
	local group = vim.api.nvim_create_augroup(
		"unified_review_codediff_" .. tostring(session.id or vim.loop.hrtime()),
		{ clear = true }
	)
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
		callback = function(event)
			if not session.ui or not event.data or event.data.tabpage ~= session.ui.codediff_tab then
				return
			end
			if event.match == "CodeDiffFileSelect" then
				session.viewed_files = session.viewed_files or {}
				if event.data.path then
					session.viewed_files[normalize_path(session, event.data.path)] = true
				end
				ensure_file(session, event.data, { select = false })
			end
			schedule_sync(session, 150)
		end,
	})
	session.ui_autocmd_group = group
end

local function session_config(session)
	local target = session.target or {}
	return {
		mode = "explorer",
		git_root = render_root(target),
		original_path = "",
		modified_path = "",
		original_revision = target.base_oid or target.base or target.base_ref,
		modified_revision = modified_revision(target),
		layout = "side-by-side",
		explorer_data = explorer_data(session),
	}
end

M._attach_review_keymaps = attach_review_keymaps

function M.sync(session)
	if not (session and session.ui and session.ui.codediff_tab) then
		debug.event("diff.sync.skip", { reason = "missing-codediff-tab", session = session and session.id })
		return false
	end
	if not vim.api.nvim_tabpage_is_valid(session.ui.codediff_tab) then
		debug.event(
			"diff.sync.skip",
			{ reason = "invalid-codediff-tab", session = session.id, tab = session.ui.codediff_tab }
		)
		return false
	end
	sync_from_codediff(session, session.ui.codediff_tab, {})
	debug.event("diff.sync", {
		session = session.id,
		left_buffer = session.ui.left_buffer,
		right_buffer = session.ui.right_buffer,
		left_window = session.ui.left_window,
		right_window = session.ui.right_window,
	})
	return true
end

function M.focus_hunk(session)
	local hunk
	if session.ui and session.ui.codediff_tab then
		local _, lifecycle = codediff_modules()
		local codediff_session = lifecycle and lifecycle.get_session(session.ui.codediff_tab)
		local changes = codediff_session
				and codediff_session.stored_diff_result
				and codediff_session.stored_diff_result.changes
			or {}
		hunk = changes[session.selection.hunk_index or 1]
	end
	if not hunk then
		local file = selection.current_file(session)
		local parsed = file and file.hunks and file.hunks[session.selection.hunk_index or 1]
		if not parsed then
			return
		end
		hunk = {
			original = { start_line = parsed.old_start },
			modified = { start_line = parsed.new_start },
		}
	end
	local win = vim.api.nvim_get_current_win()
	local side = win == session.ui.left_window and "original" or "modified"
	local range = hunk[side]
	if range and range.start_line and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_set_cursor(win, { math.max(1, range.start_line), 0 })
	end
end

function M.attach(session, tabpage)
	session.ui = session.ui or {}
	session.ui.codediff_tab = tabpage or vim.api.nvim_get_current_tabpage()
	sync_from_codediff(session, session.ui.codediff_tab, {})
	attach_file_select_autocmd(session)
	schedule_sync(session, 150)
end

function M.render(session, opts)
	opts = opts or {}
	local view = codediff_modules()
	if not view then
		vim.notify(
			"codediff.nvim is required for unified-review diff rendering",
			vim.log.levels.ERROR,
			{ title = "unified-review" }
		)
		return
	end

	if session.ui and session.ui.codediff_tab then
		local file = selection.current_file(session)
		local target = session.target or {}
		if not file then
			return
		end
		local mod_revision = modified_revision(target)
		local cfg = {
			mode = "standalone",
			git_root = render_root(target),
			original_path = file.old_path or file.path,
			modified_path = mod_revision == "WORKING" and working_path(target, file.path) or file.path,
			original_revision = target.base_oid,
			modified_revision = mod_revision,
			layout = "side-by-side",
		}
		local auto_scroll = opts.auto_scroll_to_first_hunk ~= false
		debug.event("diff.render.update", {
			session = session.id,
			file = file.path,
			auto_scroll_to_first_hunk = auto_scroll,
		})
		view.update(session.ui.codediff_tab, cfg, auto_scroll)
		schedule_sync(session, 150)
		return
	end

	local first_file = selection.current_file(session)
	local result
	result = view.create(session_config(session), first_file and detect_filetype(first_file.path) or "", function()
		sync_from_codediff(session, vim.api.nvim_get_current_tabpage(), result or {})
	end)
	if result then
		sync_from_codediff(session, vim.api.nvim_get_current_tabpage(), result)
		attach_file_select_autocmd(session)
	end
end

return M
