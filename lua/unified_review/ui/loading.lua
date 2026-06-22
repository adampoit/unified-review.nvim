local float = require("unified_review.ui.float")
local loader = require("components.loader")
local renderer = require("components.renderer")
local ui = require("components")

local M = {}

M.ns = vim.api.nvim_create_namespace("unified_review_loading")

local HIGHLIGHT_LINKS = {
	UnifiedReviewLoadingTitle = "UnifiedReviewFloatTitle",
	UnifiedReviewLoadingText = "UnifiedReviewFloatContext",
	UnifiedReviewLoadingSpinner = "UnifiedReviewFloatInfo",
}

local function document(state)
	return {
		ui.line({
			ui.loader(state.message or "Loading", {
				frame = state.frame or 0,
				hl = "UnifiedReviewLoadingText",
				spinner_hl = "UnifiedReviewLoadingSpinner",
			}),
		}),
	}
end

function M.open(opts)
	opts = opts or {}
	float.ensure_highlights(HIGHLIGHT_LINKS)
	local state = {
		message = opts.message or "Loading",
		frame = 0,
		closed = false,
	}
	local popup = float.open({
		name = opts.name or "unified-review://loading",
		document = document(state),
		ns = M.ns,
		filetype = "unified-review-loading",
		width = opts.width or 44,
		height = 1,
		min_width = opts.min_width or 28,
		max_width = opts.max_width or 80,
		min_height = 1,
		max_height = 1,
		title = opts.title or " Unified Review ",
		zindex = opts.zindex or 220,
		enter = false,
		focusable = false,
		modifiable = false,
		default_keymaps = false,
		close_on_bufleave = false,
		winhighlight = {
			FloatTitle = "UnifiedReviewLoadingTitle",
		},
	})
	state.buf = popup.buffer
	state.win = popup.window

	local timer = (vim.uv or vim.loop).new_timer()
	state.timer = timer
	timer:start(
		opts.interval or 120,
		opts.interval or 120,
		vim.schedule_wrap(function()
			if state.closed or not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
				M.close(state)
				return
			end
			state.frame = loader.frame_after(state.frame)
			vim.bo[state.buf].modifiable = true
			renderer.render(state.buf, M.ns, document(state))
			vim.bo[state.buf].modifiable = false
		end)
	)

	function state:set_message(message)
		self.message = message or self.message
		if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
			vim.bo[self.buf].modifiable = true
			renderer.render(self.buf, M.ns, document(self))
			vim.bo[self.buf].modifiable = false
		end
	end

	function state:close()
		M.close(self)
	end

	return state
end

function M.close(state)
	if not state or state.closed then
		return
	end
	state.closed = true
	if state.timer then
		state.timer:stop()
		state.timer:close()
		state.timer = nil
	end
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
	end
end

return M
