local ui = require("components")
local float = require("unified_review.ui.float")

describe("component documents in float windows", function()
	it("renders component lines and highlight extmarks", function()
		local ns = vim.api.nvim_create_namespace("components_float_spec")
		local popup = float.open({
			lines = {
				ui.line({
					ui.list({ { ui.badge("CR", { hl = "ComponentKey" }), ui.text("open") } }, { type = "horizontal" }),
				}),
				ui.text_line("Context", "ComponentContext"),
			},
			ns = ns,
			width = 40,
			height = 3,
			min_width = 40,
			max_width = 40,
			min_height = 3,
			max_height = 3,
		})

		local lines = vim.api.nvim_buf_get_lines(popup.buffer, 0, -1, false)
		local marks = vim.api.nvim_buf_get_extmarks(popup.buffer, ns, 0, -1, { details = true })
		local saw_key = false
		local saw_context = false
		for _, mark in ipairs(marks) do
			local details = mark[4] or {}
			if details.hl_group == "ComponentKey" then
				saw_key = true
			elseif details.hl_group == "ComponentContext" then
				saw_context = true
			end
		end

		popup.close()
		assert.are.same({ " CR  open", "Context" }, lines)
		assert.is_true(saw_key)
		assert.is_true(saw_context)
	end)
end)
