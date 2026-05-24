local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root
	.. "/?.lua;"
	.. root
	.. "/?/init.lua;"
	.. root
	.. "/tests/?.lua;"
	.. root
	.. "/tests/?/init.lua;"
	.. package.path

local plenary_path = vim.env.PLENARY_PATH
if not plenary_path or plenary_path == "" then
	plenary_path = vim.fn.glob("/nix/store/*plenary.nvim*/**/plenary.nvim", false, true)[1]
end

if not plenary_path or plenary_path == "" then
	error("plenary.nvim not found; set PLENARY_PATH to the plenary.nvim checkout path")
end

vim.opt.runtimepath:append(plenary_path)

local codediff_path = vim.env.CODEDIFF_PATH
if not codediff_path or codediff_path == "" then
	error("codediff.nvim not found; set CODEDIFF_PATH to the codediff.nvim checkout path")
end
vim.opt.runtimepath:append(codediff_path)
