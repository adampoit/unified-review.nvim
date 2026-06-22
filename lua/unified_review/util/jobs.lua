local M = {}

local function executable_error(cmd)
	return string.format("executable not found: %s", cmd)
end

function M.run_sync(cmd, args, opts)
	args = args or {}
	opts = opts or {}

	if vim.fn.executable(cmd) ~= 1 then
		return {
			ok = false,
			cmd = cmd,
			args = args,
			code = 127,
			stdout = "",
			stderr = executable_error(cmd),
		}
	end

	local result = vim.system(vim.list_extend({ cmd }, args), {
		cwd = opts.cwd,
		text = true,
		timeout = opts.timeout,
		stdin = opts.stdin,
	}):wait()

	return {
		ok = result.code == 0,
		cmd = cmd,
		args = args,
		code = result.code,
		stdout = result.stdout or "",
		stderr = result.stderr or "",
	}
end

function M.run(cmd, args, opts, callback)
	if type(opts) == "function" then
		callback = opts
		opts = {}
	end

	local result = M.run_sync(cmd, args, opts)
	if callback then
		vim.schedule(function()
			callback(result)
		end)
	end
	return result
end

function M.run_async(cmd, args, opts, callback)
	args = args or {}
	opts = opts or {}

	if type(opts) == "function" then
		callback = opts
		opts = {}
	end

	if vim.fn.executable(cmd) ~= 1 then
		local result = {
			ok = false,
			cmd = cmd,
			args = args,
			code = 127,
			stdout = "",
			stderr = executable_error(cmd),
		}
		if callback then
			vim.schedule(function()
				callback(result)
			end)
		end
		return nil
	end

	return vim.system(vim.list_extend({ cmd }, args), {
		cwd = opts.cwd,
		text = true,
		timeout = opts.timeout,
		stdin = opts.stdin,
	}, function(result)
		local normalized = {
			ok = result.code == 0,
			cmd = cmd,
			args = args,
			code = result.code,
			stdout = result.stdout or "",
			stderr = result.stderr or "",
		}
		if callback then
			vim.schedule(function()
				callback(normalized)
			end)
		end
	end)
end

function M.assert_ok(result)
	if result.ok then
		return result
	end

	local rendered = result.cmd .. " " .. table.concat(result.args or {}, " ")
	local message = string.format("command failed (%s): %s", result.code, rendered)
	if result.stderr ~= "" then
		message = message .. "\n" .. result.stderr
	end
	error(message, 2)
end

return M
