local make = require("components.component").make

local M = {}

M.spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

function M.spinner(frame, frames)
	frames = frames or M.spinner_frames
	if #frames == 0 then
		return ""
	end
	frame = math.max(0, tonumber(frame) or 0)
	return frames[(frame % #frames) + 1]
end

function M.component(label, opts)
	opts = opts or {}
	return make("loader", {
		label = tostring(label or "Loading"),
		frame = opts.frame,
		frames = opts.frames or M.spinner_frames,
		position = opts.position or "prefix",
		separator = opts.separator == nil and " " or opts.separator,
		hl = opts.hl,
		spinner_hl = opts.spinner_hl or opts.dot_hl or opts.hl,
	})
end

function M.frame_after(frame, delta, frames)
	frames = frames or M.spinner_frames
	local count = math.max(1, #frames)
	return ((tonumber(frame) or 0) + (delta or 1)) % count
end

return M
