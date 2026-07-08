local manager = require("unified_review.session.manager")
local schema = require("unified_review.agent_feedback.schema")
local state = require("unified_review.session.state")
local session_store = require("unified_review.persist.session_store")

local M = {}

local function now()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function err(message)
	return nil, { message = message }
end

local function read_json(path)
	if not path or path == "" then
		return err("feedback path is required")
	end
	local read_ok, lines = pcall(vim.fn.readfile, path)
	if not read_ok then
		return err("failed to read feedback file: " .. tostring(lines))
	end
	local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"), { luanil = { object = true, array = true } })
	if not ok then
		return err("failed to decode feedback JSON: " .. tostring(decoded))
	end
	return decoded, nil
end

local function write_json(path, value)
	if not path or path == "" then
		return err("output path is required")
	end
	local ok, encoded = pcall(vim.json.encode, value)
	if not ok then
		return err("failed to encode JSON: " .. tostring(encoded))
	end
	local write_ok, write_result = pcall(vim.fn.writefile, { encoded }, path)
	if not write_ok or write_result ~= 0 then
		return err("failed to write JSON file: " .. tostring(write_result))
	end
	return true, nil
end

local function ensure_session(opts)
	opts = opts or {}
	local active = state.get_active()
	if active then
		return active, nil
	end
	local target = opts.target or "current"
	if target == "current" then
		return manager.open_current_change({})
	end
	if type(target) == "table" then
		return manager.open_target(target, {})
	end
	return err("unsupported import target: " .. tostring(target))
end

local function session_has_file(session, target)
	for _, file in ipairs(session.files or {}) do
		if file.path == target.path or file.old_path == target.path then
			return true
		end
	end
	return false
end

local function dedupe_key(review, comment)
	local source = review.source or {}
	if type(source) ~= "table" or not source.name or not source.run_id or not comment.id then
		return nil
	end
	return table.concat({ tostring(source.name), tostring(source.run_id), tostring(comment.id) }, "\31")
end

local function existing_by_key(session, key)
	if not key then
		return nil
	end
	for _, thread in ipairs(session.threads or {}) do
		local agent = thread.metadata and thread.metadata.agent_feedback
		if agent and agent.dedupe_key == key then
			return thread
		end
	end
	return nil
end

local function refresh_ui(session)
	if not session or not session.ui then
		return
	end
	require("unified_review.ui.signs").place(session)
	if session._inline_visible ~= false then
		require("unified_review.ui.inline").place(session)
	end
	if session.ui.thread_panel_buf then
		require("unified_review.ui.thread_panel").render(session)
	end
	if session.ui.summary_buf then
		require("unified_review.ui.summary").render(session)
	end
end

local function comment_author(review, comment, opts)
	return comment.author or review.author or opts.author or "agent"
end

local function agent_metadata(review, comment, key, opts)
	return {
		schema = schema.SCHEMA,
		source = review.source or opts.source,
		severity = comment.severity,
		category = comment.category,
		comment_id = comment.id,
		dedupe_key = key,
		imported_at = now(),
	}
end

local function update_existing(session, thread, review, comment, key, opts)
	thread.target = comment.target
	thread.metadata = thread.metadata or {}
	thread.metadata.export = true
	thread.metadata.agent_feedback = agent_metadata(review, comment, key, opts)
	local first = thread.comments and thread.comments[1]
	if first then
		first.body = comment.body
		first.author = comment_author(review, comment, opts)
		first.target = comment.target
		first.updated_at = now()
		first.metadata = first.metadata or {}
		first.metadata.agent_feedback = thread.metadata.agent_feedback
	end
	local ok, persist_err = pcall(session_store.write, session)
	if not ok then
		return nil, { message = persist_err }
	end
	return thread, nil
end

local function import_summary(session, review, opts)
	if not review.summary or review.summary == "" then
		return
	end
	session.metadata = session.metadata or {}
	session.metadata.agent_feedback = session.metadata.agent_feedback or {}
	session.metadata.agent_feedback.summary = {
		body = review.summary,
		author = review.author or opts.author or "agent",
		source = review.source or opts.source,
		imported_at = now(),
	}
	pcall(session_store.write, session)
end

function M.import(review, opts)
	opts = opts or {}
	local normalized, validation_err = schema.validate(review)
	if not normalized then
		return nil, validation_err
	end
	local session, session_err = ensure_session(opts)
	if not session then
		return nil, session_err
	end

	local result = {
		imported_threads = 0,
		imported_comments = 0,
		updated_threads = 0,
		skipped = {},
		warnings = {},
		session_id = session.id,
	}

	import_summary(session, normalized, opts)
	for index, comment in ipairs(normalized.comments or {}) do
		if not session_has_file(session, comment.target) then
			table.insert(
				result.skipped,
				{ index = index, path = comment.target.path, reason = "file is not in review session" }
			)
		else
			local key = dedupe_key(normalized, comment)
			local existing = existing_by_key(session, key)
			if existing then
				local _, update_err = update_existing(session, existing, normalized, comment, key, opts)
				if update_err then
					table.insert(result.warnings, update_err.message or "failed to update existing comment")
				else
					result.updated_threads = result.updated_threads + 1
					result.imported_comments = result.imported_comments + 1
				end
			else
				local metadata = { export = true, agent_feedback = agent_metadata(normalized, comment, key, opts) }
				local thread, create_err = manager.create_comment(comment.body, comment.target, {
					author = comment_author(normalized, comment, opts),
					metadata = metadata,
					notify = false,
					auto_copy = false,
					refresh_ui = false,
				})
				if not thread then
					table.insert(result.warnings, create_err and create_err.message or "failed to import comment")
				else
					result.imported_threads = result.imported_threads + 1
					result.imported_comments = result.imported_comments + 1
				end
			end
		end
	end
	if opts.refresh_ui ~= false then
		refresh_ui(session)
	end
	return result, nil
end

function M.import_file(path, opts)
	local review, read_err = read_json(path)
	if not review then
		return nil, read_err
	end
	return M.import(review, opts)
end

local function target_artifact(target, item)
	return {
		schema = "unified-review.agent-selection.v1",
		selected_at = now(),
		label = item and item.label or "Review target",
		description = item and item.description or nil,
		target = target,
		open_command = "UnifiedReview current",
	}
end

function M.select_target(opts)
	opts = opts or {}
	local discovered, discovery_err = require("unified_review.session.target_discovery").discover(opts)
	if not discovered then
		return nil, discovery_err
	end
	return require("unified_review.ui.target_picker").open({
		discovery = discovered,
		on_select = function(target, item)
			local artifact = target_artifact(target, item)
			if opts.path then
				write_json(opts.path, artifact)
			end
			if type(opts.on_select) == "function" then
				opts.on_select(artifact)
			end
			if opts.quit then
				vim.cmd("qa")
			end
		end,
		on_cancel = opts.on_cancel,
	})
end

local function line_ranges(file)
	local ranges = {}
	for _, hunk in ipairs(file.hunks or {}) do
		table.insert(ranges, {
			left = { start = hunk.old_start, count = hunk.old_count },
			right = { start = hunk.new_start, count = hunk.new_count },
			header = hunk.header,
		})
	end
	return ranges
end

function M.context(opts)
	opts = opts or {}
	local session, session_err = ensure_session(opts)
	if not session then
		return nil, session_err
	end
	local files = {}
	for _, file in ipairs(session.files or {}) do
		table.insert(files, {
			path = file.path,
			old_path = file.old_path,
			status = file.status,
			additions = file.additions,
			deletions = file.deletions,
			raw_patch = file.raw_patch,
			line_ranges = line_ranges(file),
		})
	end
	return {
		schema = "unified-review.agent-context.v1",
		generated_at = now(),
		session = { id = session.id, kind = session.kind, target = session.target },
		files = files,
		target_examples = {
			{ kind = "file", path = "lua/example.lua" },
			{ kind = "line", path = "lua/example.lua", side = "right", line = 42 },
			{
				kind = "range",
				path = "lua/example.lua",
				start_side = "right",
				start_line = 50,
				side = "right",
				line = 58,
			},
		},
	},
		nil
end

function M.write_context(path, opts)
	local context, context_err = M.context(opts)
	if not context then
		return nil, context_err
	end
	local ok, write_err = write_json(path, context)
	if not ok then
		return nil, write_err
	end
	return { path = path, session_id = context.session and context.session.id, files = #(context.files or {}) }, nil
end

return M
