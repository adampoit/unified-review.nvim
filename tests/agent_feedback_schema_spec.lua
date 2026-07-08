local schema = require("unified_review.agent_feedback.schema")

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local fixture_root = root .. "/tests/fixtures/agent-feedback"

local function fixtures(kind)
	return vim.fn.glob(fixture_root .. "/" .. kind .. "/*.json", false, true)
end

local function decode(path)
	return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"), { luanil = { object = true, array = true } })
end

describe("agent feedback schema fixtures", function()
	it("accepts every valid shared fixture", function()
		for _, path in ipairs(fixtures("valid")) do
			local result, err = schema.validate(decode(path))
			assert.is_nil(err, path)
			assert.is_not_nil(result, path)
		end
	end)

	it("rejects every invalid shared fixture", function()
		for _, path in ipairs(fixtures("invalid")) do
			local result, err = schema.validate(decode(path))
			assert.is_nil(result, path)
			assert.is_not_nil(err, path)
		end
	end)
end)
