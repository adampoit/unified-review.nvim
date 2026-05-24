local changed_file = require("unified_review.domain.changed_file")
local local_comment_provider = require("unified_review.providers.comments.local_store")
local comment_target = require("unified_review.domain.comment_target")
local git_provider = require("unified_review.providers.diff.git_local")
local github_pr_provider = require("unified_review.providers.diff.github_pr")
local github_comment_provider = require("unified_review.providers.comments.github_review")
local lifecycle = require("unified_review.session.lifecycle")
local selection = require("unified_review.session.selection")
local state = require("unified_review.session.state")
local layout = require("unified_review.ui.layout")
local config = require("unified_review.config")
local export = require("unified_review.export")
local review_target = require("unified_review.domain.review_target")
local review_thread = require("unified_review.domain.review_thread")
local target_discovery = require("unified_review.session.target_discovery")

local M = {}

local function notify_error(message, operation)
	local op_prefix = operation and ("[" .. operation .. "] ") or ""
	vim.notify(op_prefix .. (message or "unknown error"), vim.log.levels.ERROR, { title = "unified-review" })
end

-- Refresh all UI surfaces after comment changes.
-- Uses session-scoped debounce to avoid redundant renders during rapid operations.
local function refresh_ui(session)
	if not session or not session.ui then
		return
	end
	-- Initialize debouncer per session
	if not session._ui_debounce then
		session._ui_debounce = require("unified_review.util.debounce").debounce(80, function()
			if not session or session.closed then
				return
			end
			require("unified_review.ui.signs").place(session)
			if session._inline_visible ~= false then
				require("unified_review.ui.inline").place(session)
			else
				require("unified_review.ui.inline").clear(session)
			end
			if session.ui and session.ui.thread_panel_buf then
				require("unified_review.ui.thread_panel").render(session)
			end
			if session.ui and session.ui.summary_buf then
				require("unified_review.ui.summary").render(session)
			end
		end)
	end
	session._ui_debounce()
end

local function comments_for(session)
	if session and session.kind == "github_pr" then
		return github_comment_provider
	end
	return local_comment_provider
end

local function load_comments(session)
	local threads, err = comments_for(session).load(session)
	if err then
		notify_error(err.message or err.stderr or "failed to load review comments", "comments")
	end
	return threads, err
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
	})[status] or "modified"
end

local function find_existing_file(files, file)
	for _, existing in ipairs(files or {}) do
		if existing.path == file.path or existing.old_path == file.path or existing.path == file.old_path then
			return existing
		end
	end
	return nil
end

local function files_from_codediff(codediff_session, existing_files)
	local files = {}
	local seen = {}
	local explorer = codediff_session.explorer
	local status_result = explorer and explorer.status_result or {}
	local function add(file)
		if not file or not file.path or seen[file.path] then
			return
		end
		seen[file.path] = true
		local existing = find_existing_file(existing_files, file)
		table.insert(
			files,
			changed_file.new({
				path = file.path,
				old_path = file.old_path,
				status = normalize_status(file.status),
				additions = existing and existing.additions or 0,
				deletions = existing and existing.deletions or 0,
				hunks = existing and existing.hunks or {},
				raw_patch = existing and existing.raw_patch or "",
				metadata = existing and existing.metadata or {},
			})
		)
	end
	for _, group in ipairs({ "unstaged", "staged", "conflicts" }) do
		for _, file in ipairs(status_result[group] or {}) do
			add(file)
		end
	end
	if #files == 0 and codediff_session.modified_path and codediff_session.modified_path ~= "" then
		add({ path = codediff_session.modified_path, old_path = codediff_session.original_path, status = "M" })
	end
	return files
end

function M.open_local(opts)
	opts = opts or {}
	local session, err = git_provider.open(opts)
	if not session then
		notify_error(err and (err.message or err.stderr) or "failed to open local review", "open")
		return nil, err
	end

	session.id = session.id or table.concat({ "local", session.target.base_oid, session.target.head_oid }, ":")
	session.kind = "local_git"
	load_comments(session)
	selection.initialize(session)
	state.set_active(session)
	layout.open(session)
	vim.notify(
		string.format("Loaded %d changed file(s)", #session.files),
		vim.log.levels.INFO,
		{ title = "unified-review" }
	)
	return session, nil
end

function M.open_target(target, opts)
	opts = opts or {}
	target = review_target.new(target or {})
	if target.kind == "github_pr" then
		local session, err = github_pr_provider.open(target)
		if not session then
			notify_error(err and (err.message or err.stderr) or "failed to open GitHub PR review", "open-pr")
			return nil, err
		end
		session.id = session.id
			or table.concat(
				{ "github", session.target.owner or "", session.target.repo or "", session.target.number or "" },
				":"
			)
		session.kind = "github_pr"
		load_comments(session)
		selection.initialize(session)
		state.set_active(session)
		layout.open(session)
		vim.notify(
			string.format(
				"Loaded GitHub PR #%s with %d changed file(s)",
				tostring(session.target.number),
				#session.files
			),
			vim.log.levels.INFO,
			{ title = "unified-review" }
		)
		return session, nil
	end
	if target.kind == "jj" then
		local ok_provider, jj_provider = pcall(require, "unified_review.providers.diff.jj_local")
		if not ok_provider or type(jj_provider.open) ~= "function" then
			local provider_err = { message = "jj diff provider is not available" }
			notify_error(provider_err.message, "open-jj")
			return nil, provider_err
		end
		local session, err = jj_provider.open(target)
		if not session then
			notify_error(err and (err.message or err.stderr) or "failed to open jj review", "open-jj")
			return nil, err
		end
		session.id = session.id
			or table.concat({ "jj", target.resolved_base or target.base, target.resolved_head or target.head }, ":")
		session.kind = "local_jj"
		load_comments(session)
		selection.initialize(session)
		state.set_active(session)
		layout.open(session)
		return session, nil
	end
	return M.open_local(target)
end

function M.pick_review_target(opts)
	opts = opts or {}
	local discovered, err = target_discovery.discover(opts)
	if not discovered then
		notify_error(err and (err.message or err.stderr) or "failed to discover review targets", "pick")
		return nil, err
	end
	return require("unified_review.ui.target_picker").open({
		discovery = discovered,
		on_select = function(target, item)
			M.open_target(target, { picker_item = item })
		end,
		on_cancel = opts.on_cancel,
	})
end

function M.open_current_change(opts)
	opts = opts or {}
	local item, err = target_discovery.current_target(opts)
	if not item then
		notify_error(err and (err.message or err.stderr) or "failed to discover current change", "current")
		return nil, err
	end
	for _, note in ipairs(item.warnings or (item.target and item.target.fallback_notes) or {}) do
		vim.notify(note, vim.log.levels.INFO, { title = "unified-review" })
	end
	return M.open_target(item.target, { picker_item = item })
end

function M.open_pr(number_or_url)
	return M.open_target(review_target.github_pr({
		number = tonumber(number_or_url),
		url = tonumber(number_or_url) and nil or number_or_url,
	}))
end

function M.attach_codediff(tabpage, opts)
	opts = opts or {}
	local ok, codediff_lifecycle = pcall(require, "codediff.ui.lifecycle")
	if not ok then
		return nil, { message = "codediff.nvim is not available" }
	end
	tabpage = tabpage or vim.api.nvim_get_current_tabpage()
	local codediff_session = codediff_lifecycle.get_session(tabpage)
	if not codediff_session then
		return nil, { message = "No active CodeDiff session" }
	end

	local session = state.get_active()
	if not session or session.ui == nil or session.ui.codediff_tab ~= tabpage then
		session = {
			id = table.concat({
				"codediff",
				codediff_session.git_root or "",
				codediff_session.original_revision or "",
				codediff_session.modified_revision or "",
			}, ":"),
			kind = "codediff_local",
			provider = "codediff",
			target = {
				kind = "codediff",
				root = codediff_session.git_root,
				base_oid = codediff_session.original_revision,
				head_oid = codediff_session.modified_revision,
			},
			files = files_from_codediff(codediff_session),
			threads = {},
			editable = codediff_session.modified_revision == "WORKING",
		}
	else
		session.files = files_from_codediff(codediff_session, session.files)
	end

	load_comments(session)
	selection.initialize(session)
	state.set_active(session)
	require("unified_review.ui.diff_view").attach(session, tabpage)
	if not opts.silent then
		vim.notify("Attached unified-review to CodeDiff", vim.log.levels.INFO, { title = "unified-review" })
	end
	return session, nil
end

function M.active()
	return state.get_active()
end

function M.close()
	local session = state.get_active()
	if not session then
		vim.notify("No active review session", vim.log.levels.INFO, { title = "unified-review" })
		return false
	end
	pcall(require("unified_review.persist.session_store").write, session)
	lifecycle.close(session)
	state.clear_active()
	vim.notify("Closed review session", vim.log.levels.INFO, { title = "unified-review" })
	return true
end

function M.refresh()
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	local diff_provider = session.kind == "github_pr" and github_pr_provider
		or session.kind == "local_jj" and require("unified_review.providers.diff.jj_local")
		or git_provider
	local refreshed, err = diff_provider.refresh(session)
	if not refreshed then
		notify_error(err and (err.message or err.stderr) or "failed to refresh review")
		return nil, err
	end
	refreshed.id = session.id
	refreshed.kind = session.kind
	refreshed.metadata = vim.tbl_deep_extend("force", refreshed.metadata or {}, session.metadata or {})
	load_comments(refreshed)
	selection.initialize(refreshed)
	state.set_active(refreshed)
	return refreshed, nil
end

function M.create_comment(body, target)
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	body = body or ""
	if body == "" then
		return nil, { message = "Comment body is required" }
	end
	target = target or selection.current_target(session)
	if not target then
		return nil, { message = "No comment target at cursor" }
	end
	local thread, err = comments_for(session).create_thread(session, target, body)
	if not thread then
		notify_error(err and err.message or "failed to create comment")
		return nil, err
	end
	refresh_ui(session)
	if config.options.local_git.auto_copy_on_add then
		export.copy(comments_for(session).list_threads(session), { format = "markdown", session = session })
	end
	vim.notify(
		"Created draft comment at " .. comment_target.label(thread.target),
		vim.log.levels.INFO,
		{ title = "unified-review" }
	)
	return thread, nil
end

function M.reply(thread_id, body)
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	body = body or ""
	if body == "" then
		return nil, { message = "Reply body is required" }
	end
	thread_id = thread_id or (comments_for(session).list_threads(session)[1] or {}).id
	local comment, err = comments_for(session).reply(session, thread_id, body)
	if not comment then
		notify_error(err and err.message or "failed to create reply")
		return nil, err
	end
	refresh_ui(session)
	vim.notify("Created draft reply", vim.log.levels.INFO, { title = "unified-review" })
	return comment, nil
end

function M.list_threads(path)
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	return comments_for(session).list_threads(session, path), nil
end

function M.edit_draft(comment_id, body)
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	body = body or ""
	if body == "" then
		return nil, { message = "Comment body is required" }
	end
	local comment, err = comments_for(session).edit_draft(session, comment_id, body)
	if not comment then
		notify_error(err and err.message or "failed to edit draft")
		return nil, err
	end
	refresh_ui(session)
	vim.notify("Edited draft " .. comment_id, vim.log.levels.INFO, { title = "unified-review" })
	return comment, nil
end

function M.set_thread_state(thread_id, thread_state)
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	thread_id = thread_id or (selection.current_thread(session) or {}).id
	if not thread_id then
		return nil, { message = "No thread selected" }
	end
	local thread, err = comments_for(session).resolve_thread(session, thread_id, thread_state)
	if not thread then
		notify_error(err and err.message or "failed to update thread")
		return nil, err
	end
	refresh_ui(session)
	vim.notify(
		"Updated thread " .. thread_id .. " to " .. thread.state,
		vim.log.levels.INFO,
		{ title = "unified-review" }
	)
	return thread, nil
end

function M.resolve_thread(thread_id)
	return M.set_thread_state(thread_id, "resolved")
end

function M.reopen_thread(thread_id)
	return M.set_thread_state(thread_id, "open")
end

function M.clear_comments()
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	local ok, err = comments_for(session).clear(session)
	if not ok then
		notify_error(err and err.message or "failed to clear review comments")
		return nil, err
	end
	refresh_ui(session)
	vim.notify("Cleared review comments", vim.log.levels.INFO, { title = "unified-review" })
	return true, nil
end

function M.undo_comment()
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	local label, err = comments_for(session).undo(session)
	if not label then
		notify_error(err and err.message or "failed to undo comment change")
		return nil, err
	end
	refresh_ui(session)
	vim.notify("Undid " .. label, vim.log.levels.INFO, { title = "unified-review" })
	return true, nil
end

function M.delete_draft(comment_id)
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	local ok, err = comments_for(session).delete_draft(session, comment_id)
	if not ok then
		notify_error(err and err.message or "failed to delete draft")
		return nil, err
	end
	refresh_ui(session)
	vim.notify("Deleted draft " .. comment_id, vim.log.levels.INFO, { title = "unified-review" })
	return true, nil
end

function M.toggle_thread_export(thread_id)
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	thread_id = thread_id or (selection.current_thread(session) or {}).id
	if not thread_id then
		return nil, { message = "No thread selected" }
	end
	for _, thread in ipairs(session.threads or {}) do
		if thread.id == thread_id then
			review_thread.toggle_exported(thread)
			pcall(require("unified_review.persist.session_store").write, session)
			refresh_ui(session)
			local state_label = review_thread.is_exported(thread) and "marked for export" or "unmarked for export"
			vim.notify("Thread " .. thread_id .. " " .. state_label, vim.log.levels.INFO, { title = "unified-review" })
			return thread, nil
		end
	end
	return nil, { message = "thread not found: " .. tostring(thread_id) }
end

function M.publish_drafts_to_github()
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	if session.kind ~= "github_pr" then
		return nil, { message = "Draft publishing is only available for GitHub PR reviews" }
	end
	local result, err = comments_for(session).publish_drafts(session)
	if not result then
		notify_error(err and err.message or "failed to publish drafts to GitHub", "publish-drafts")
		return nil, err
	end
	refresh_ui(session)
	vim.notify(
		string.format("Published %d draft comment(s) to GitHub pending review", result.comments or 0),
		vim.log.levels.INFO,
		{ title = "unified-review" }
	)
	return result, nil
end

function M.publish_drafts(pr_ref, opts)
	opts = opts or {}
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	if session.kind == "github_pr" then
		return M.publish_drafts_to_github()
	end
	local publisher = require("unified_review.providers.comments.publish")
	local report, err = publisher.publish(session, vim.tbl_extend("force", opts, { pr_ref = pr_ref }))
	if not report then
		notify_error(err and err.message or "failed to publish drafts", "publish-drafts")
		return nil, err
	end
	refresh_ui(session)
	local lines = publisher.format_report(report)
	if not opts.silent then
		require("unified_review.ui.float").open({
			name = "unified-review://draft-publish-report",
			lines = lines,
			modifiable = false,
			filetype = "markdown",
			min_width = 62,
			max_width = 90,
			max_height = math.floor(vim.o.lines * 0.85),
			title = "draft publishing",
			enter = true,
			zindex_key = "summary",
			footer = { "[q/Esc] close" },
		})
	end
	vim.notify(
		string.format("Published %d draft comment(s); %d failed", #(report.successes or {}), #(report.failures or {})),
		#(report.failures or {}) > 0 and vim.log.levels.WARN or vim.log.levels.INFO,
		{ title = "unified-review" }
	)
	return report, nil
end

function M.submit_review(event, body)
	local session = state.get_active()
	if not session then
		return nil, { message = "No active review session" }
	end
	if session.kind ~= "github_pr" then
		require("unified_review.ui.summary").open()
		return true, nil
	end
	local submitted, err = comments_for(session).submit_review(session, event or "COMMENT", body or "")
	if not submitted then
		notify_error(err and err.message or "failed to submit GitHub review", "submit")
		return nil, err
	end
	refresh_ui(session)
	vim.notify("Submitted GitHub review", vim.log.levels.INFO, { title = "unified-review" })
	return submitted, nil
end

M.selection = selection

return M
