local manager = require("unified_review.session.manager")
local selection = require("unified_review.session.selection")
local comment_editor = require("unified_review.ui.comment_editor")
local float = require("unified_review.ui.float")

local M = {}

local registered = false

local function slice(args, start_index)
	local result = {}
	for index = start_index, #(args or {}) do
		table.insert(result, args[index])
	end
	return result
end

local function command_with_args(command, args)
	return vim.tbl_extend("force", command or {}, {
		args = table.concat(args or {}, " "),
		fargs = args or {},
	})
end

local function parse_local_args(args)
	local base, head, range_kind = require("unified_review.integrations.git").parse_range(args or {})
	return { base = base, head = head, range_kind = range_kind }
end

local function review_local(command)
	manager.open_local(parse_local_args(command.fargs or {}))
end

local function review_current_change()
	manager.open_current_change({})
end

local function review_pr(command)
	local args = command.fargs or {}
	manager.open_pr(args[1])
end

local function review_comment()
	local session = manager.active()
	if not session then
		vim.notify("No active review session", vim.log.levels.INFO, { title = "unified-review" })
		return
	end
	local current_target = selection.ensure_comment_target(session)
	if not current_target then
		vim.notify(
			"No changed file is selected for commenting. Open a file in the review diff, then run :UnifiedReview comment again.",
			vim.log.levels.INFO,
			{ title = "unified-review" }
		)
		return
	end
	session._comment_editor_open = true
	comment_editor.open({ target = current_target })
end

local function review_reply(command)
	local args = command.fargs or {}
	local thread_id = args[1] and args[1]:match("^thread") and args[1]
		or vim.api.nvim_get_current_line():match("^(thread[%w_-]+)")
	local session = manager.active()
	if not session then
		vim.notify("No active review session", vim.log.levels.INFO, { title = "unified-review" })
		return
	end
	thread_id = thread_id or (manager.selection.current_thread(session) or {}).id
	if not thread_id then
		vim.notify("No thread selected", vim.log.levels.INFO, { title = "unified-review" })
		return
	end
	comment_editor.open({ thread_id = thread_id })
end

local function review_threads()
	local session = manager.active()
	if not session then
		vim.notify("No active review session", vim.log.levels.INFO, { title = "unified-review" })
		return
	end
	require("unified_review.ui.thread_panel").toggle(session)
end

local function review_summary()
	require("unified_review.ui.summary").open()
end

local function review_submit(command)
	local session = manager.active()
	if not session or session.kind ~= "github_pr" then
		review_summary()
		return
	end
	local args = command.fargs or {}
	local event_arg = (args[1] or "comment"):lower():gsub("-", "_")
	local event = ({
		comment = "COMMENT",
		approve = "APPROVE",
		approved = "APPROVE",
		request_changes = "REQUEST_CHANGES",
		changes = "REQUEST_CHANGES",
	})[event_arg] or "COMMENT"
	local body_start = ({ comment = true, approve = true, approved = true, request_changes = true, changes = true })[event_arg]
			and 2
		or 1
	local body = table.concat(args, " ", body_start)
	local _, err = manager.submit_review(event, body)
	if err then
		vim.notify(err.message or "failed to submit review", vim.log.levels.ERROR, { title = "unified-review" })
	end
end

local function review_publish_drafts(command)
	local args = command.fargs or {}
	local _, err = manager.publish_drafts(args[1])
	if err then
		vim.notify(err.message or "failed to publish drafts", vim.log.levels.ERROR, { title = "unified-review" })
	end
end

local function review_save(command)
	local args = command.fargs or {}
	require("unified_review.ui.summary").save(args[1], args[2] or "markdown")
end

local function thread_id_from(command)
	local args = command.fargs or {}
	return args[1] or vim.api.nvim_get_current_line():match("^(thread[%w_-]+)")
end

local function review_clear()
	local ok = vim.fn.confirm("Clear all review comments?", "&Yes\n&No", 2)
	if ok ~= 1 then
		return
	end
	local _, err = manager.clear_comments()
	if err then
		vim.notify(err.message or "failed to clear review comments", vim.log.levels.ERROR, { title = "unified-review" })
	end
end

local function review_resolve_thread(command)
	local _, err = manager.resolve_thread(thread_id_from(command))
	if err then
		vim.notify(err.message or "failed to resolve thread", vim.log.levels.ERROR, { title = "unified-review" })
	end
end

local function review_reopen_thread(command)
	local _, err = manager.reopen_thread(thread_id_from(command))
	if err then
		vim.notify(err.message or "failed to reopen thread", vim.log.levels.ERROR, { title = "unified-review" })
	end
end

local function review_toggle_export(command)
	local _, err = manager.toggle_thread_export(thread_id_from(command))
	if err then
		vim.notify(err.message or "failed to toggle export marker", vim.log.levels.ERROR, { title = "unified-review" })
	end
end

local function review_edit_draft(command)
	local args = command.fargs or {}
	local comment_id = args[1]
	if not comment_id then
		local session = manager.active()
		local thread = session and manager.selection.current_thread(session)
		comment_id = thread and thread.comments and thread.comments[1] and thread.comments[1].id
		if comment_id then
			comment_editor.open({ thread_id = thread.id })
			return
		end
		vim.notify("No draft selected", vim.log.levels.INFO, { title = "unified-review" })
		return
	end
	local body = table.concat(args, " ", 2)
	if body == "" then
		vim.notify("Body is required", vim.log.levels.ERROR, { title = "unified-review" })
		return
	end
	local _, err = manager.edit_draft(comment_id, body)
	if err then
		vim.notify(err.message or "failed to edit draft", vim.log.levels.ERROR, { title = "unified-review" })
	end
end

local function comment_id_under_cursor()
	local line = vim.api.nvim_get_current_line()
	return line:match("(comment[%w_-]+)") or line:match("review%-comment:([^ ]+)")
end

local function review_delete_draft(command)
	local args = command.fargs or {}
	local comment_id = args[1] or comment_id_under_cursor()
	if not comment_id then
		local session = manager.active()
		local thread = session and manager.selection.current_thread(session)
		comment_id = thread and thread.comments and thread.comments[1] and thread.comments[1].id
		if not comment_id then
			vim.notify("No draft selected", vim.log.levels.INFO, { title = "unified-review" })
			return
		end
	end
	local _, err = manager.delete_draft(comment_id)
	if err then
		vim.notify(err.message or "failed to delete draft", vim.log.levels.ERROR, { title = "unified-review" })
	end
end

local function review_undo()
	local _, err = manager.undo_comment()
	if err then
		vim.notify(err.message or "failed to undo comment change", vim.log.levels.ERROR, { title = "unified-review" })
	end
end

local function review_status()
	local session = manager.active()
	if not session then
		vim.notify("No active review session", vim.log.levels.INFO, { title = "unified-review" })
		return
	end
	local status = require("unified_review.ui.status")
	vim.notify(status.format(session), vim.log.levels.INFO, { title = "unified-review" })
end

local function review_help()
	local session = manager.active()
	if session then
		session._review_modal_open = true
	end
	local lines = {
		"# unified-review keymaps",
		"",
		"## File panel",
		"<CR>          open selected file",
		"]f / [f       next / previous file",
		"]h / [h       next / previous hunk",
		"q             close review surface",
		"",
		"## Diff buffers",
		"<leader>rc    new comment at cursor",
		"<leader>rr    reply to thread under cursor",
		"<leader>rt    open thread panel",
		"<leader>rS    show review summary",
		"<leader>re    toggle export marker for selected thread",
		"]t / [t       next / previous thread",
		"",
		"## Commands",
		":UnifiedReview                         open target picker",
		":UnifiedReview local [base] [head]     start local review",
		":UnifiedReview current                 open current jj/Git change",
		":UnifiedReview pr [number|url]        open current or explicit pull request review",
		":UnifiedReview close                   close review session",
		":UnifiedReview comment                 open comment editor at cursor",
		":UnifiedReview reply [thread-id]       reply to thread",
		":UnifiedReview threads                 show project-wide review overview",
		":UnifiedReview summary                 open review summary buffer",
		":UnifiedReview save [path] [format]    save marked threads as markdown or minimal text",
		":UnifiedReview publish-drafts [pr]     publish drafts to a GitHub pending review",
		":UnifiedReview toggle-export [thread]  mark/unmark a thread for export",
		":UnifiedReview status                  show review session status",
		":UnifiedReview help                    show this help",
	}
	float.open({
		name = "unified-review://help",
		lines = lines,
		modifiable = false,
		filetype = "markdown",
		min_width = 60,
		max_width = 80,
		max_height = math.floor(vim.o.lines * 0.85),
		title = "unified-review help",
		enter = true,
		zindex_key = "help",
		footer = { "[q/Esc] close" },
		on_close = function()
			if session and manager.active() == session then
				session._review_modal_open = false
			end
		end,
	})
end

local subcommands = {
	["local"] = { callback = review_local, complete = "target" },
	current = { callback = review_current_change },
	["current-change"] = { callback = review_current_change },
	pr = { callback = review_pr },
	summary = { callback = review_summary },
	submit = { callback = review_submit },
	["publish-drafts"] = { callback = review_publish_drafts },
	publish = { callback = review_publish_drafts },
	save = { callback = review_save, complete = "file" },
	close = { callback = manager.close },
	comment = { callback = review_comment },
	reply = { callback = review_reply },
	["edit-draft"] = { callback = review_edit_draft },
	["delete-draft"] = { callback = review_delete_draft },
	["delete-comment"] = { callback = review_delete_draft },
	clear = { callback = review_clear },
	["resolve-thread"] = { callback = review_resolve_thread },
	resolve = { callback = review_resolve_thread },
	["reopen-thread"] = { callback = review_reopen_thread },
	reopen = { callback = review_reopen_thread },
	["toggle-export"] = { callback = review_toggle_export },
	["export"] = { callback = review_toggle_export },
	threads = { callback = review_threads },
	undo = { callback = review_undo },
	status = { callback = review_status },
	help = { callback = review_help },
}

local subcommand_names = {
	"local",
	"current",
	"current-change",
	"pr",
	"comment",
	"reply",
	"threads",
	"summary",
	"submit",
	"publish-drafts",
	"publish",
	"save",
	"close",
	"status",
	"help",
	"edit-draft",
	"delete-draft",
	"delete-comment",
	"clear",
	"resolve-thread",
	"reopen-thread",
	"toggle-export",
	"export",
	"undo",
}

local target_candidates = { "origin/main", "origin/master", "HEAD~1..HEAD", "HEAD" }

local function matching(candidates, arglead)
	local matches = {}
	for _, candidate in ipairs(candidates) do
		if candidate:find(arglead, 1, true) == 1 then
			table.insert(matches, candidate)
		end
	end
	return matches
end

local function unified_review(command)
	local args = command.fargs or {}
	if #args == 0 then
		manager.pick_review_target({})
		return
	end
	local subcommand = subcommands[args[1]:lower()]
	if subcommand then
		subcommand.callback(command_with_args(command, slice(args, 2)))
		return
	end
	manager.open_local(parse_local_args(args))
end

local function unified_review_complete(arglead, cmdline)
	local words = vim.split(cmdline, "%s+", { trimempty = true })
	local subcommand = words[2] and words[2]:lower()
	if subcommand == "save" then
		return vim.fn.getcompletion(arglead, "file")
	end
	if subcommand == "local" or not subcommands[subcommand] then
		local candidates = vim.list_extend(vim.deepcopy(subcommand_names), target_candidates)
		return matching(candidates, arglead)
	end
	return {}
end

local command_specs = {
	UnifiedReview = { callback = unified_review, opts = { nargs = "*", complete = unified_review_complete } },
}

function M.setup()
	if registered then
		return
	end

	for name, spec in pairs(command_specs) do
		vim.api.nvim_create_user_command(name, spec.callback, spec.opts)
	end

	registered = true
end

return M
