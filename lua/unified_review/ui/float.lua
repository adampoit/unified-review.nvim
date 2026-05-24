local badge = require("components.badge")
local divider = require("components.divider")
local renderer = require("components.renderer")

local M = {}

local ZINDEX = {
	comment_editor = 200,
	thread_preview = 80,
	help = 65,
	submit = 52,
	threads = 52,
	default = 50,
}

M.HIGHLIGHT_LINKS = {
	UnifiedReviewFloatNormal = "NormalFloat",
	UnifiedReviewFloatBorder = "FloatBorder",
	UnifiedReviewFloatTitle = "FloatTitle",
	UnifiedReviewFloatFooter = "Comment",
	UnifiedReviewFloatHeader = "Title",
	UnifiedReviewFloatContext = "Comment",
	UnifiedReviewFloatBadge = "Pmenu",
	UnifiedReviewFloatSelection = "CursorLine",
	UnifiedReviewFloatSeparator = "FloatBorder",
	UnifiedReviewFloatKey = "PmenuSel",
	UnifiedReviewFloatKeyLabel = "Comment",
	UnifiedReviewFloatSection = "Title",
	UnifiedReviewFloatMuted = "Comment",
	UnifiedReviewFloatDim = "NonText",
	UnifiedReviewFloatAccent = "Special",
	UnifiedReviewFloatWarning = "WarningMsg",
	UnifiedReviewFloatSuccess = "DiagnosticOk",
	UnifiedReviewFloatInfo = "DiagnosticInfo",
}

M.badge = badge.render
M.divider = divider.render

local function clamp(value, min_value, max_value)
	return math.max(min_value, math.min(max_value, value))
end

function M.ensure_highlights(extra_links)
	local links = vim.tbl_extend("force", M.HIGHLIGHT_LINKS, extra_links or {})
	for group, link in pairs(links) do
		pcall(vim.api.nvim_set_hl, 0, group, { default = true, link = link })
	end
end

function M.winhighlight(overrides)
	local groups = vim.tbl_extend("force", {
		NormalFloat = "UnifiedReviewFloatNormal",
		CursorLine = "UnifiedReviewFloatSelection",
		FloatBorder = "UnifiedReviewFloatBorder",
		FloatTitle = "UnifiedReviewFloatTitle",
		FloatFooter = "UnifiedReviewFloatFooter",
	}, overrides or {})
	local parts = {}
	for from, to in pairs(groups) do
		table.insert(parts, string.format("%s:%s", from, to))
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

function M.add_highlight(buf, ns, group, lnum, start_col, end_col)
	if not group or not lnum or not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	pcall(vim.api.nvim_buf_add_highlight, buf, ns, group, lnum, start_col or 0, end_col or -1)
end

local function size(lines, opts)
	opts = opts or {}
	local max_width = opts.max_width or math.floor(vim.o.columns * 0.8)
	local min_width = opts.min_width or 40
	local max_height = opts.max_height or math.floor(vim.o.lines * 0.75)
	local min_height = opts.min_height or 1
	local width = opts.width
	if not width then
		width = min_width
		for _, line in ipairs(lines or {}) do
			width = math.max(width, vim.fn.strdisplaywidth(line))
		end
		width = width + 2
	end
	width = clamp(math.floor(width), min_width, math.max(max_width, min_width))
	local height = opts.height or math.min(math.max(#(lines or {}), min_height), math.max(max_height, 1))
	height = clamp(math.floor(height), 1, math.max(max_height, 1))
	return width, height
end

--- Render a native floating-window footer with keymap hints, if provided.
local function footer_line(opts)
	if not opts.footer then
		return nil
	end
	if type(opts.footer) == "string" then
		return opts.footer ~= "" and (" " .. opts.footer .. " ") or nil
	end
	if #opts.footer == 0 then
		return nil
	end
	return "  " .. table.concat(opts.footer, "  │  ")
end

local function set_buf_options(buf, options)
	for name, value in pairs(options or {}) do
		pcall(vim.api.nvim_set_option_value, name, value, { buf = buf })
	end
end

local function set_win_options(win, options)
	for name, value in pairs(options or {}) do
		pcall(vim.api.nvim_set_option_value, name, value, { win = win, scope = "local" })
	end
end

local function make_popup(buf, win)
	local popup = { bufnr = buf, winid = win }

	function popup:unmount()
		if self.winid and vim.api.nvim_win_is_valid(self.winid) then
			vim.api.nvim_win_close(self.winid, true)
		end
		if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
			vim.api.nvim_buf_delete(self.bufnr, { force = true })
		end
	end

	function popup:map(mode, key, handler, opts)
		opts = vim.tbl_extend("force", opts or {}, { buffer = self.bufnr })
		vim.keymap.set(mode, key, handler, opts)
	end

	function popup:on(event, handler, options)
		vim.api.nvim_create_autocmd(
			event,
			vim.tbl_extend("force", options or {}, {
				buffer = self.bufnr,
				callback = handler,
			})
		)
	end

	return popup
end

function M.open(opts)
	opts = opts or {}
	M.ensure_highlights(opts.highlight_links)
	local document = opts.document or opts.lines or {}
	local lines = renderer.lines(document)
	local footer = footer_line(opts)
	local w, h = size(lines, opts)
	local zindex = opts.zindex or ZINDEX[opts.zindex_key or "default"] or ZINDEX.default

	local buf = vim.api.nvim_create_buf(false, true)
	set_buf_options(
		buf,
		vim.tbl_extend("force", {
			modifiable = true,
			buftype = "nofile",
			bufhidden = "wipe",
			swapfile = false,
		}, opts.buf_options or {})
	)
	if opts.name then
		pcall(vim.api.nvim_buf_set_name, buf, opts.name)
	end
	if opts.filetype then
		vim.bo[buf].filetype = opts.filetype
	end
	if opts.ns then
		renderer.render(buf, opts.ns, document)
	else
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end
	if opts.modifiable == false then
		vim.bo[buf].modifiable = false
	end

	local win_config = {
		relative = opts.relative or "editor",
		row = opts.row or math.max(0, math.floor((vim.o.lines - h) / 2)),
		col = opts.col or math.max(0, math.floor((vim.o.columns - w) / 2)),
		width = w,
		height = h,
		style = "minimal",
		noautocmd = true,
		focusable = opts.focusable ~= false,
		zindex = zindex,
		border = opts.border or "rounded",
		title = opts.title or "",
		title_pos = "center",
	}
	if footer then
		win_config.footer = footer
		win_config.footer_pos = "center"
	end

	local win = vim.api.nvim_open_win(buf, opts.enter ~= false, win_config)
	local win_options = vim.tbl_extend("force", {
		winhighlight = M.winhighlight(opts.winhighlight),
	}, opts.win_options or {})
	set_win_options(win, win_options)

	local popup = make_popup(buf, win)
	local closed = false

	local function close()
		if closed then
			return
		end
		closed = true
		pcall(popup.unmount, popup)
		if opts.on_close then
			pcall(opts.on_close)
		end
	end

	if opts.default_keymaps ~= false then
		popup:map("n", "<Esc>", close, { noremap = true, silent = true })
		popup:map("n", "q", close, { noremap = true, silent = true })
	end

	if not opts.enter and opts.close_on_bufleave ~= false then
		popup:on("BufLeave", close, { once = true })
	end

	return { buffer = buf, window = win, close = close, popup = popup }
end

return M
