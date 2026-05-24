local discovery = require("unified_review.session.target_discovery")
local float = require("unified_review.ui.float")
local ui = require("components")
local renderer = require("components.renderer")

local M = {}

M.ns = vim.api.nvim_create_namespace("unified_review_target_picker")

local HIGHLIGHT_LINKS = {
	UnifiedReviewPickerTitle = "UnifiedReviewFloatTitle",
	UnifiedReviewPickerContext = "UnifiedReviewFloatContext",
	UnifiedReviewPickerBadge = "UnifiedReviewFloatBadge",
	UnifiedReviewPickerBorder = "UnifiedReviewFloatBorder",
	UnifiedReviewPickerFooter = "UnifiedReviewFloatFooter",
	UnifiedReviewPickerInput = "String",
	UnifiedReviewPickerSelection = "UnifiedReviewFloatSelection",
	UnifiedReviewPickerSeparator = "UnifiedReviewFloatSeparator",
	UnifiedReviewPickerWarning = "UnifiedReviewFloatWarning",
	UnifiedReviewPickerKey = "UnifiedReviewFloatKey",
	UnifiedReviewPickerSection = "UnifiedReviewFloatSection",
	UnifiedReviewPickerMuted = "UnifiedReviewFloatMuted",
	UnifiedReviewPickerBase = "UnifiedReviewFloatInfo",
	UnifiedReviewPickerHead = "UnifiedReviewFloatSuccess",
}

local function clamp(value, min_value, max_value)
	return math.max(min_value, math.min(max_value, value))
end

local function display_width(text)
	return vim.fn.strdisplaywidth(text or "")
end

local function truncate(text, width)
	text = tostring(text or "")
	if display_width(text) <= width then
		return text
	end
	return vim.fn.strcharpart(text, 0, math.max(0, width - 1)) .. "…"
end

local function pad(lines, count)
	while #lines < count do
		table.insert(lines, "")
	end
	while #lines > count do
		table.remove(lines)
	end
	return lines
end

local function ensure_highlights()
	float.ensure_highlights(HIGHLIGHT_LINKS)
end

local HORIZONTAL_PADDING = "  "

local function content_width(state)
	return math.max(10, (state.width or 80) - vim.fn.strdisplaywidth(HORIZONTAL_PADDING) - 2)
end

local key_items

local function style_lines(lines)
	return ui.inset(lines, { text = HORIZONTAL_PADDING })
end

local function key_hint_components(state)
	local hints = {}
	for _, item in ipairs(key_items(state)) do
		table.insert(hints, {
			ui.badge(item.label, { hl = "UnifiedReviewPickerKey" }),
			item.text and item.text ~= "" and ui.text(item.text) or nil,
		})
	end
	return {
		ui.list(hints, {
			type = "horizontal",
			separator = ui.sep(nil, { hl = "UnifiedReviewPickerSeparator" }),
		}),
	}
end

local function active_mode(state)
	return (state and state.mode) or "list"
end

function key_items(state)
	if state and state.filtering then
		return {
			{ label = "type", text = "filter" },
			{ label = "Esc", text = "nav" },
			{ label = "BS", text = "delete" },
			{ label = "C-l", text = "clear" },
		}
	end
	local mode = active_mode(state)
	if mode == "commit" then
		return {
			{ label = "b", text = "base" },
			{ label = "h", text = "head" },
			{ label = "j/k", text = "move" },
			{ label = "/", text = "filter" },
			{ label = "CR", text = "open" },
		}
	end
	if mode == "pr" then
		return {
			{ label = "j/k", text = "move" },
			{ label = "/", text = "filter" },
			{ label = "CR", text = "open" },
			{ label = "Esc", text = "back" },
		}
	end
	if mode == "custom" then
		return {
			{ label = "type", text = "edit" },
			{ label = "CR", text = "open" },
			{ label = "Esc", text = "back" },
			{ label = "C-l", text = "clear" },
		}
	end
	return {
		{ label = "j/k", text = "move" },
		{ label = "/", text = "filter" },
		{ label = "CR", text = "open" },
		{ label = "q/Esc", text = "close" },
	}
end

local function key_line(state)
	return ui.line(key_hint_components(state or {}), {
		hl = "UnifiedReviewPickerFooter",
		truncate_width = content_width(state or {}),
	})
end

local function context_text_line(value)
	return ui.text_line(value, "UnifiedReviewPickerContext")
end

local function section_line(value)
	return ui.section(value, { hl = "UnifiedReviewPickerSection" })
end

local function warning_line(value)
	return ui.text_line("⚠ " .. tostring(value or ""), "UnifiedReviewPickerWarning")
end

local function label_value_line(label, value, value_group)
	return ui.line({
		ui.text(label, "UnifiedReviewPickerContext"),
		ui.text(" " .. tostring(value or ""), value_group),
	})
end

local function divider_line(width)
	return ui.divider(width, { hl = "UnifiedReviewPickerSeparator" })
end

local function target_summary(target)
	if not target then
		return ""
	end
	if target.kind == "jj" then
		return string.format(
			"jj %s → %s",
			target.raw_base or target.base_revset or target.base,
			target.raw_head or target.head_revset or target.head or "@"
		)
	end
	if target.kind == "github_pr" then
		return "GitHub PR " .. tostring(target.number or target.url or "")
	end
	return string.format("local %s %s", target.raw_base or target.base or "", target.raw_head or target.head or "HEAD")
end

local function matches_filter(values, filter)
	filter = vim.trim(filter or ""):lower()
	if filter == "" then
		return true
	end
	local haystack = table.concat(values or {}, " "):lower()
	return haystack:find(filter, 1, true) ~= nil
end

local function filtered_items(state)
	local items = state.items or {}
	local filter = state.filter or ""
	if vim.trim(filter) == "" then
		return items
	end
	local result = {}
	for _, item in ipairs(items) do
		if matches_filter({ item.label or "", item.description or "", item.badge or "" }, filter) then
			table.insert(result, item)
		end
	end
	return result
end

local function selected_item(state)
	local items = filtered_items(state)
	if #items == 0 then
		return nil, items
	end
	state.selected = clamp(state.selected or 1, 1, #items)
	return items[state.selected], items
end

local function filtered_commits(state)
	local commits = state.commits or {}
	local filter = state.commit_filter or ""
	local result = {}
	for index, commit in ipairs(commits) do
		if
			matches_filter({
				commit.short_id or "",
				commit.oid or "",
				commit.change_id or "",
				commit.refs or "",
				commit.description or "",
			}, filter)
		then
			table.insert(result, { index = index, commit = commit })
		end
	end
	return result
end

local function selected_commit(state)
	local entries = filtered_commits(state)
	if #entries == 0 then
		return nil, entries, nil
	end
	local selected = state.commit_selected or entries[1].index
	for position, entry in ipairs(entries) do
		if entry.index == selected then
			state.commit_selected = entry.index
			return entry.commit, entries, position
		end
	end
	state.commit_selected = entries[1].index
	return entries[1].commit, entries, 1
end

local function select_first_filtered_commit(state)
	local entries = filtered_commits(state)
	state.commit_selected = entries[1] and entries[1].index or nil
end

local function filtered_prs(state)
	local prs = state.prs or {}
	local filter = state.pr_filter or ""
	local result = {}
	for index, pr in ipairs(prs) do
		if
			matches_filter({
				tostring(pr.number or ""),
				pr.title or "",
				pr.author or "",
				pr.base_name or "",
				pr.head_name or "",
			}, filter)
		then
			table.insert(result, { index = index, pr = pr })
		end
	end
	return result
end

local function selected_pr(state)
	local entries = filtered_prs(state)
	if #entries == 0 then
		return nil, entries, nil
	end
	local selected = state.pr_selected or entries[1].index
	for position, entry in ipairs(entries) do
		if entry.index == selected then
			state.pr_selected = entry.index
			return entry.pr, entries, position
		end
	end
	state.pr_selected = entries[1].index
	return entries[1].pr, entries, 1
end

local function select_first_filtered_pr(state)
	local entries = filtered_prs(state)
	state.pr_selected = entries[1] and entries[1].index or nil
end

local function context_line(state)
	local disc = state.discovery or {}
	local provider = disc.provider or disc.mode or "none"
	local root = disc.root or disc.cwd or vim.fn.getcwd()
	return context_text_line(
		string.format("Provider: %s · Root: %s", provider, truncate(root, math.max(24, content_width(state) - 18)))
	)
end

local function render_target_list(state, lines)
	local item_under_cursor, items = selected_item(state)
	table.insert(lines, context_line(state))
	table.insert(
		lines,
		label_value_line(
			"Filter:",
			(state.filter and state.filter ~= "") and state.filter or "<type to narrow>",
			"UnifiedReviewPickerInput"
		)
	)
	table.insert(lines, section_line("Targets"))
	local list_height = state.list_height or 8
	local target_list = ui.list(items, {
		selectable = true,
		height = list_height,
		selected = state.selected or 1,
		selected_hl = "UnifiedReviewPickerSelection",
		truncate_width = content_width(state),
		empty = {
			"  No targets match the active filter",
			"  Press C-l to clear or C-r to refresh discovery",
		},
		prefix = function(ctx)
			return string.format("%s %s ", ctx.marker, ctx.disabled and "×" or " ")
		end,
		render = function(entry)
			local badge_label = entry.badge or "target"
			local badge_padding = string.rep(" ", math.max(0, 10 - display_width(" " .. badge_label .. " ")))
			local children = {
				ui.list({
					{
						ui.badge(badge_label, { hl = "UnifiedReviewPickerBadge" }),
						ui.text(badge_padding .. (entry.label or "")),
					},
				}, { type = "horizontal", separator = false }),
			}
			if entry.description and entry.description ~= "" then
				table.insert(children, ui.text(" — " .. entry.description, "UnifiedReviewPickerContext"))
			end
			return ui.line(children)
		end,
	})
	vim.list_extend(lines, target_list.document)
	table.insert(lines, divider_line(content_width(state)))
	table.insert(lines, section_line("Preview"))
	local preview = {}
	if state.validation_error then
		table.insert(preview, warning_line(state.validation_error))
	end
	if item_under_cursor then
		table.insert(preview, item_under_cursor.label or "Review target")
		if item_under_cursor.kind == "commit_range" then
			table.insert(preview, "Mark base with b, head with h, then open with CR.")
		elseif item_under_cursor.kind == "github_pr_picker" then
			table.insert(preview, "Pick an open pull request to review.")
		elseif item_under_cursor.kind == "custom" then
			table.insert(preview, "Type a Git ref/range or jj revset/range.")
		else
			table.insert(preview, target_summary(item_under_cursor.target))
		end
		for _, line in ipairs(item_under_cursor.summary_lines or {}) do
			table.insert(preview, line)
		end
		for _, warning in ipairs(item_under_cursor.warnings or {}) do
			table.insert(preview, warning_line(warning))
		end
	else
		table.insert(preview, "No target selected")
	end
	pad(preview, state.preview_height or 7)
	for _, line in ipairs(preview) do
		if renderer.is_component(line) then
			table.insert(lines, ui.line({ line }, { truncate_width = content_width(state) }))
		else
			table.insert(lines, truncate(line, content_width(state)))
		end
	end
end

local function render_custom(state, lines)
	local mode = (state.discovery and state.discovery.mode) or "git"
	local is_github_pr = state.custom_kind == "github_pr"
	table.insert(lines, context_line(state))
	table.insert(lines, section_line(is_github_pr and "GitHub PR" or "Custom target"))
	table.insert(lines, label_value_line("Input:", (state.custom_input or "") .. "█", "UnifiedReviewPickerInput"))
	if state.validation_error then
		table.insert(lines, warning_line(state.validation_error))
	else
		table.insert(lines, "Press CR to normalize and open, Esc to return to targets.")
	end
	table.insert(lines, section_line("Examples:"))
	if is_github_pr then
		table.insert(lines, "  123")
		table.insert(lines, "  https://github.com/owner/repo/pull/123")
	elseif mode == "jj" then
		table.insert(lines, "  trunk()          (trunk() → @)")
		table.insert(lines, "  origin/main      (main@origin → @ when resolvable)")
		table.insert(lines, "  main@origin..@   (explicit jj range)")
	else
		table.insert(lines, "  origin/main         (defaults to origin/main...HEAD)")
		table.insert(lines, "  origin/main...HEAD  (three-dot, commits since merge-base)")
		table.insert(lines, "  origin/main..HEAD   (two-dot, direct ref comparison)")
		table.insert(lines, "  HEAD~3..HEAD")
	end
end

local function render_pr_picker(state, lines)
	local prs = state.prs or {}
	local _, entries, selected_position = selected_pr(state)
	table.insert(lines, context_line(state))
	table.insert(
		lines,
		label_value_line(
			"Filter:",
			(state.pr_filter and state.pr_filter ~= "") and state.pr_filter or "<type to narrow pull requests>",
			"UnifiedReviewPickerInput"
		)
	)
	table.insert(lines, section_line("Open pull requests"))
	local list_height = state.pr_height or 12
	local empty_lines
	if #prs == 0 then
		empty_lines = { "  No open pull requests were found" }
	elseif #entries == 0 then
		empty_lines = { "  No pull requests match the active filter", "  Press C-l to clear the filter" }
	end
	local pr_list = ui.list(entries, {
		selectable = true,
		height = list_height,
		selected = selected_position or 1,
		selected_hl = "UnifiedReviewPickerSelection",
		truncate_width = content_width(state),
		empty = empty_lines,
		render = function(entry)
			local pr = entry.pr
			local draft = pr.is_draft and " draft" or ""
			local branch = pr.base_name and pr.head_name and string.format(" %s←%s", pr.base_name, pr.head_name) or ""
			return ui.line({
				ui.badge("#" .. tostring(pr.number or "?"), { hl = "UnifiedReviewPickerBadge" }),
				ui.text(string.format(" %-42s", truncate((pr.title or "Untitled") .. draft, 42))),
				ui.text(branch, "UnifiedReviewPickerContext"),
				pr.author and ui.text(" @" .. pr.author, "UnifiedReviewPickerContext") or nil,
			})
		end,
	})
	vim.list_extend(lines, pr_list.document)
	table.insert(lines, divider_line(content_width(state)))
	table.insert(lines, section_line("Preview"))
	if state.validation_error then
		table.insert(lines, warning_line(state.validation_error))
	end
	local pr = selected_pr(state)
	if pr then
		table.insert(lines, string.format("GitHub PR #%s", tostring(pr.number or "?")))
		table.insert(lines, pr.title or "Untitled")
		if pr.base_name and pr.head_name then
			table.insert(lines, string.format("%s ← %s", pr.base_name, pr.head_name))
		end
		if pr.url then
			table.insert(lines, pr.url)
		end
	else
		table.insert(lines, "No pull request selected")
	end
end

local function render_commit_range(state, lines)
	local commits = state.commits or {}
	local _, entries, selected_position = selected_commit(state)
	table.insert(lines, context_line(state))
	table.insert(
		lines,
		label_value_line(
			"Filter:",
			(state.commit_filter and state.commit_filter ~= "") and state.commit_filter or "<type to narrow commits>",
			"UnifiedReviewPickerInput"
		)
	)
	table.insert(lines, section_line("Commit range"))
	local list_height = state.commit_height or 12
	local empty_lines
	if #commits == 0 then
		empty_lines = { "  No recent commits or changes were found" }
	elseif #entries == 0 then
		empty_lines = { "  No commits match the active filter", "  Press C-l to clear the filter" }
	end
	local commit_list = ui.list(entries, {
		selectable = true,
		height = list_height,
		selected = selected_position or 1,
		selected_hl = "UnifiedReviewPickerSelection",
		truncate_width = content_width(state),
		empty = empty_lines,
		render = function(entry)
			local index = entry.index
			local commit = entry.commit
			local markers = {}
			if index == state.base_index then
				table.insert(markers, "B")
			end
			if index == state.head_index then
				table.insert(markers, "H")
			end
			local marker_label = #markers > 0 and table.concat(markers, "/") or nil
			local refs = commit.refs and commit.refs ~= "" and (" " .. commit.refs) or ""
			local change = commit.change_id and commit.provider == "jj" and (" " .. commit.change_id) or ""
			local children = {}
			if marker_label then
				table.insert(
					children,
					ui.list({
						{
							ui.badge(marker_label, { hl = "UnifiedReviewPickerBadge" }),
							ui.text(string.rep(" ", math.max(0, 5 - display_width(" " .. marker_label .. " ")))),
						},
					}, { type = "horizontal", separator = false })
				)
			else
				table.insert(children, ui.text(string.rep(" ", 6)))
			end
			table.insert(
				children,
				ui.text(
					string.format(
						"%-12s%s%s  %s",
						commit.short_id or commit.oid or "",
						change,
						refs,
						commit.description or ""
					)
				)
			)
			return ui.line(children)
		end,
	})
	vim.list_extend(lines, commit_list.document)
	table.insert(lines, divider_line(content_width(state)))
	table.insert(lines, section_line("Selection"))
	if state.validation_error then
		table.insert(lines, warning_line(state.validation_error))
	end
	local base = state.base_index and commits[state.base_index]
	local head = state.head_index and commits[state.head_index]
	table.insert(
		lines,
		label_value_line(
			"Base:",
			base and (base.short_id .. " " .. (base.description or "")) or "<unset>",
			"UnifiedReviewPickerBase"
		)
	)
	table.insert(
		lines,
		label_value_line(
			"Head:",
			head and (head.short_id .. " " .. (head.description or "")) or "<unset>",
			"UnifiedReviewPickerHead"
		)
	)
end

function M.render_document(state)
	state = state or {}
	state.width = state.width or 80
	state.height = state.height or 24
	local lines = { key_line(state), "" }
	if state.mode == "custom" then
		render_custom(state, lines)
	elseif state.mode == "commit" then
		render_commit_range(state, lines)
	elseif state.mode == "pr" then
		render_pr_picker(state, lines)
	else
		render_target_list(state, lines)
	end
	pad(lines, state.height)
	return style_lines(lines)
end

function M.render_lines(state)
	return renderer.lines(M.render_document(state))
end

local function render(state)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	local document = M.render_document(state)
	vim.bo[state.buf].modifiable = true
	renderer.render(state.buf, M.ns, document)
	vim.bo[state.buf].modifiable = false
end

local function focus_picker(state)
	if state.closed or not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return
	end
	if vim.api.nvim_get_current_win() ~= state.win then
		pcall(vim.api.nvim_set_current_win, state.win)
	end
end

local function install_focus_autocmds(state)
	state.autocmd_group = vim.api.nvim_create_augroup("unified_review_target_picker_" .. tostring(state.buf), {
		clear = true,
	})
	vim.api.nvim_create_autocmd("FocusGained", {
		group = state.autocmd_group,
		callback = function()
			vim.schedule(function()
				if M.current == state then
					focus_picker(state)
				end
			end)
		end,
	})
end

local function close(state)
	if state.closed then
		return
	end
	state.closed = true
	if state.autocmd_group then
		pcall(vim.api.nvim_del_augroup_by_id, state.autocmd_group)
	end
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
	end
	if M.current == state then
		M.current = nil
	end
end

local function load_commits(state)
	local disc = state.discovery or {}
	local commits, err = discovery.recent_commits({
		mode = disc.mode,
		cwd = disc.root or disc.cwd,
		root = disc.root,
		git_root = disc.git_root,
		limit = state.commit_limit or 30,
	})
	state.commits = commits or {}
	state.commit_filter = state.commit_filter or ""
	state.commit_selected = #state.commits >= 1 and 1 or nil
	state.head_index = #state.commits >= 1 and 1 or nil
	state.base_index = #state.commits >= 2 and 2 or nil
	state.validation_error = err and (err.message or err.stderr) or nil
end

local function load_prs(state)
	local disc = state.discovery or {}
	local prs, err = discovery.open_pull_requests({
		cwd = disc.root or disc.cwd,
		root = disc.root,
		limit = state.pr_limit or 50,
	})
	state.prs = prs or {}
	state.pr_filter = state.pr_filter or ""
	state.pr_selected = #state.prs >= 1 and 1 or nil
	state.validation_error = err and (err.message or err.stderr) or nil
end

local function select_current(state)
	state.validation_error = nil
	if state.mode == "custom" then
		local disc = state.discovery or {}
		local normalizer = state.custom_kind == "github_pr" and discovery.normalize_github_pr
			or discovery.normalize_custom
		local target, err = normalizer(state.custom_input, {
			mode = disc.mode,
			cwd = disc.root or disc.cwd,
			root = disc.root,
			git_root = disc.git_root,
		})
		if not target then
			state.validation_error = err and err.message or "Unable to normalize target"
			return
		end
		close(state)
		state.on_select(target, { kind = "custom", label = "Custom target" })
		return
	end
	if state.mode == "commit" then
		local disc = state.discovery or {}
		local target, err = discovery.target_from_commit_range(state.commits, state.base_index, state.head_index, {
			mode = disc.mode,
			cwd = disc.root or disc.cwd,
			root = disc.root,
			git_root = disc.git_root,
		})
		if not target then
			state.validation_error = err and err.message or "Invalid commit range"
			return
		end
		close(state)
		state.on_select(target, { kind = "commit_range", label = "Commit range" })
		return
	end
	if state.mode == "pr" then
		local pr = selected_pr(state)
		if not pr or not pr.target then
			state.validation_error = "No pull request is selected"
			return
		end
		close(state)
		state.on_select(pr.target, { kind = "github_pr", label = "GitHub PR #" .. tostring(pr.number or "?") })
		return
	end
	local current = selected_item(state)
	if not current then
		state.validation_error = "No target is selected"
		return
	end
	if current.disabled then
		state.validation_error = (current.warnings and current.warnings[1]) or "This picker option is unavailable"
		return
	end
	if current.kind == "custom" then
		state.mode = "custom"
		state.custom_kind = nil
		state.custom_input = ""
		state.filtering = false
		return
	end
	if current.kind == "github_pr_picker" then
		state.mode = "pr"
		load_prs(state)
		state.filtering = false
		return
	end
	if current.kind == "commit_range" then
		state.mode = "commit"
		load_commits(state)
		state.filtering = false
		return
	end
	close(state)
	state.on_select(current.target, current)
end

local function refresh_discovery(state)
	local disc = state.discovery or {}
	local refreshed, err = discovery.discover({ cwd = disc.root or disc.cwd })
	if not refreshed then
		state.validation_error = err and (err.message or err.stderr) or "Unable to discover review targets"
		return
	end
	state.discovery = refreshed
	state.items = refreshed.items or {}
	state.selected = 1
	state.validation_error = nil
	if state.mode == "commit" then
		load_commits(state)
	end
end

local function enter_filter_mode(state)
	state.filtering = true
end

local function exit_filter_mode(state)
	state.filtering = false
end

local function maybe_exit_filter_mode(state)
	if not state.filtering then
		return
	end
	local current = (state.mode == "custom" and state.custom_input)
		or (state.mode == "commit" and state.commit_filter)
		or (state.mode == "pr" and state.pr_filter)
		or state.filter
	if vim.trim(current or "") == "" then
		state.filtering = false
	end
end

local function select_by_shortcut(state, char)
	if state.mode ~= "list" or state.filtering then
		return false
	end
	char = (char or ""):lower()
	if char == "" then
		return false
	end
	local items = filtered_items(state)
	local function matching_index(prefix)
		for index, item in ipairs(items) do
			local badge = tostring(item.badge or ""):lower()
			local label = tostring(item.label or ""):lower()
			local id = tostring(item.id or ""):lower()
			if badge:sub(1, #prefix) == prefix or label:sub(1, #prefix) == prefix or id:sub(1, #prefix) == prefix then
				return index
			end
		end
		return nil
	end
	local shortcut = (state.shortcut_input or "") .. char
	local index = matching_index(shortcut)
	if not index then
		shortcut = char
		index = matching_index(shortcut)
	end
	if not index then
		state.shortcut_input = ""
		return false
	end
	state.shortcut_input = shortcut
	state.selected = index
	state.validation_error = nil
	return true
end

local function append_filter_char(state, char)
	state.validation_error = nil
	if state.mode == "custom" then
		state.custom_input = (state.custom_input or "") .. char
	elseif state.mode == "commit" then
		state.commit_filter = (state.commit_filter or "") .. char
		select_first_filtered_commit(state)
	elseif state.mode == "pr" then
		state.pr_filter = (state.pr_filter or "") .. char
		select_first_filtered_pr(state)
	elseif state.mode == "list" then
		state.filter = (state.filter or "") .. char
		state.selected = 1
	end
end

local function backspace(state)
	state.validation_error = nil
	if state.mode == "custom" then
		local input = state.custom_input or ""
		state.custom_input = vim.fn.strcharpart(input, 0, math.max(0, vim.fn.strchars(input) - 1))
	elseif state.mode == "commit" then
		local filter = state.commit_filter or ""
		state.commit_filter = vim.fn.strcharpart(filter, 0, math.max(0, vim.fn.strchars(filter) - 1))
		select_first_filtered_commit(state)
	elseif state.mode == "pr" then
		local filter = state.pr_filter or ""
		state.pr_filter = vim.fn.strcharpart(filter, 0, math.max(0, vim.fn.strchars(filter) - 1))
		select_first_filtered_pr(state)
	elseif state.mode == "list" then
		local filter = state.filter or ""
		state.filter = vim.fn.strcharpart(filter, 0, math.max(0, vim.fn.strchars(filter) - 1))
		state.selected = 1
	end
end

local function move_selection(state, delta)
	state.validation_error = nil
	if state.mode == "commit" then
		local _, entries, selected_position = selected_commit(state)
		if #entries == 0 then
			return
		end
		local next_position = clamp((selected_position or 1) + delta, 1, #entries)
		state.commit_selected = entries[next_position].index
	elseif state.mode == "pr" then
		local _, entries, selected_position = selected_pr(state)
		if #entries == 0 then
			return
		end
		local next_position = clamp((selected_position or 1) + delta, 1, #entries)
		state.pr_selected = entries[next_position].index
	elseif state.mode == "list" then
		local _, items = selected_item(state)
		state.selected = clamp((state.selected or 1) + delta, 1, math.max(1, #items))
	elseif state.mode == "custom" then
		append_filter_char(state, delta < 0 and "k" or "j")
	end
end

local function map_key(state, lhs, handler)
	vim.keymap.set("n", lhs, function()
		handler()
		render(state)
	end, { buffer = state.buf, silent = true, nowait = true })
end

local function set_keymaps(state)
	for byte = 33, 126 do
		local char = string.char(byte)
		map_key(state, char, function()
			if state.mode == "custom" or state.filtering then
				append_filter_char(state, char)
			else
				select_by_shortcut(state, char)
			end
		end)
	end
	map_key(state, "/", function()
		if state.mode == "custom" then
			append_filter_char(state, "/")
		else
			enter_filter_mode(state)
		end
	end)
	map_key(state, "<Space>", function()
		if state.mode == "custom" or state.filtering then
			append_filter_char(state, " ")
		end
	end)
	map_key(state, "j", function()
		if state.mode == "custom" or state.filtering then
			append_filter_char(state, "j")
		else
			move_selection(state, 1)
		end
	end)
	map_key(state, "k", function()
		if state.mode == "custom" or state.filtering then
			append_filter_char(state, "k")
		else
			move_selection(state, -1)
		end
	end)
	map_key(state, "<Down>", function()
		move_selection(state, 1)
	end)
	map_key(state, "<Up>", function()
		move_selection(state, -1)
	end)
	local function page_delta()
		if state.mode == "commit" then
			return state.commit_height or 12
		end
		if state.mode == "pr" then
			return state.pr_height or 12
		end
		return state.list_height or 8
	end
	map_key(state, "<C-d>", function()
		move_selection(state, page_delta())
	end)
	map_key(state, "<PageDown>", function()
		move_selection(state, page_delta())
	end)
	map_key(state, "<C-u>", function()
		move_selection(state, -page_delta())
	end)
	map_key(state, "<PageUp>", function()
		move_selection(state, -page_delta())
	end)
	map_key(state, "<CR>", function()
		select_current(state)
		state.filtering = false
	end)
	map_key(state, "<BS>", function()
		backspace(state)
		maybe_exit_filter_mode(state)
	end)
	map_key(state, "<Del>", function()
		backspace(state)
		maybe_exit_filter_mode(state)
	end)
	map_key(state, "<C-l>", function()
		state.validation_error = nil
		if state.mode == "commit" then
			state.commit_filter = ""
			select_first_filtered_commit(state)
		elseif state.mode == "pr" then
			state.pr_filter = ""
			select_first_filtered_pr(state)
		elseif state.mode == "custom" then
			state.custom_input = ""
		else
			state.filter = ""
			state.selected = 1
		end
		state.filtering = false
	end)
	map_key(state, "<C-r>", function()
		refresh_discovery(state)
		state.filtering = false
	end)
	map_key(state, "b", function()
		if state.mode == "commit" and state.commit_selected and not state.filtering then
			state.base_index = state.commit_selected
		else
			append_filter_char(state, "b")
		end
	end)
	map_key(state, "h", function()
		if state.mode == "commit" and state.commit_selected and not state.filtering then
			state.head_index = state.commit_selected
		else
			append_filter_char(state, "h")
		end
	end)
	map_key(state, "q", function()
		if state.filtering then
			append_filter_char(state, "q")
		else
			close(state)
			if state.on_cancel then
				state.on_cancel()
			end
		end
	end)
	map_key(state, "<Esc>", function()
		if state.filtering then
			exit_filter_mode(state)
		elseif state.mode == "custom" or state.mode == "commit" or state.mode == "pr" then
			state.mode = "list"
			state.validation_error = nil
			state.filtering = false
		else
			close(state)
			if state.on_cancel then
				state.on_cancel()
			end
		end
	end)
end

function M.open(opts)
	opts = opts or {}
	local disc = opts.discovery
	local err
	if not disc then
		disc, err = discovery.discover(opts.discovery_opts or {})
	end
	if not disc then
		vim.notify(err and (err.message or err.stderr) or "Unable to discover review targets", vim.log.levels.ERROR, {
			title = "unified-review",
		})
		return nil, err
	end
	local width = opts.width or clamp(math.floor(vim.o.columns * 0.72), 64, 108)
	local height = opts.height or 24
	local row = opts.row or math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
	local col = opts.col or math.max(0, math.floor((vim.o.columns - width) / 2))
	ensure_highlights()
	local popup = float.open({
		name = "unified-review://target-picker",
		lines = {},
		modifiable = false,
		filetype = "unified-review-picker",
		width = width,
		height = height,
		min_width = width,
		max_width = width,
		min_height = height,
		max_height = height,
		row = row,
		col = col,
		title = " ◉ Unified Review ",
		zindex = 70,
		default_keymaps = false,
		win_options = {
			cursorline = true,
			winhighlight = float.winhighlight({
				FloatBorder = "UnifiedReviewPickerBorder",
				FloatTitle = "UnifiedReviewPickerTitle",
				FloatFooter = "UnifiedReviewPickerFooter",
			}),
		},
	})
	local buf = popup.buffer
	local win = popup.window
	local state = {
		mode = "list",
		discovery = disc,
		items = disc.items or {},
		filter = "",
		commit_filter = "",
		pr_filter = "",
		selected = 1,
		width = width,
		height = height,
		list_height = opts.list_height or 6,
		preview_height = opts.preview_height or 8,
		commit_height = opts.commit_height or 12,
		pr_height = opts.pr_height or 12,
		buf = buf,
		win = win,
		on_select = opts.on_select or function() end,
		on_cancel = opts.on_cancel,
		filtering = false,
	}
	M.current = state
	install_focus_autocmds(state)
	set_keymaps(state)
	render(state)
	return state, nil
end

function M.close_current()
	if M.current then
		close(M.current)
		return true
	end
	return false
end

return M
