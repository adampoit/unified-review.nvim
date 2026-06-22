local jobs = require("unified_review.util.jobs")

describe("jobs", function()
	it("captures successful command output", function()
		local result = jobs.run_sync("printf", { "hello" })
		assert.is_true(result.ok)
		assert.are.equal(0, result.code)
		assert.are.equal("hello", result.stdout)
	end)

	it("reports missing executables", function()
		local result = jobs.run_sync("unified-review-missing-command", {})
		assert.is_false(result.ok)
		assert.are.equal(127, result.code)
		assert.matches("executable not found", result.stderr)
	end)

	it("runs commands asynchronously", function()
		local async_result
		jobs.run_async("printf", { "hello" }, function(result)
			async_result = result
		end)

		assert.is_true(vim.wait(1000, function()
			return async_result ~= nil
		end))
		assert.is_true(async_result.ok)
		assert.are.equal("hello", async_result.stdout)
	end)
end)
