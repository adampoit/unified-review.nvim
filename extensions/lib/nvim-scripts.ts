import { luaJson, luaString } from "./nvim.ts";

export function buildReviewExportInit(
  reviewPath: string,
  diagnosticsPath: string,
): string {
  return (
    [
      `local review_path = ${luaString(reviewPath)}`,
      `local diagnostics_path = ${luaString(diagnosticsPath)}`,
      "local function collect_messages()",
      "  local ok, result = pcall(vim.api.nvim_exec2, 'messages', { output = true })",
      "  return ok and result.output or ''",
      "end",
      "local function modified_buffers()",
      "  local buffers = {}",
      "  for _, buf in ipairs(vim.api.nvim_list_bufs()) do",
      "    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then",
      "      table.insert(buffers, { name = vim.api.nvim_buf_get_name(buf), buftype = vim.bo[buf].buftype })",
      "    end",
      "  end",
      "  return buffers",
      "end",
      "local function write_diagnostics(status, fields)",
      "  fields = fields or {}",
      "  fields.status = status",
      "  fields.v_errmsg = vim.v.errmsg",
      "  fields.v_exiting = vim.v.exiting",
      "  fields.messages = collect_messages()",
      "  fields.modified_buffers = modified_buffers()",
      "  pcall(vim.fn.writefile, { vim.json.encode(fields) }, diagnostics_path)",
      "end",
      "vim.api.nvim_create_autocmd('VimLeavePre', { callback = function()",
      "  local ok, summary = pcall(require, 'unified_review.ui.summary')",
      "  if not ok then",
      "    write_diagnostics('error', { message = tostring(summary) })",
      "    return",
      "  end",
      "  if type(summary.save_active) ~= 'function' then",
      "    local legacy_ok, legacy_err = pcall(vim.cmd, 'UnifiedReview save ' .. vim.fn.fnameescape(review_path))",
      "    write_diagnostics(legacy_ok and 'saved' or 'error', { message = legacy_ok and 'saved via legacy command' or tostring(legacy_err) })",
      "    return",
      "  end",
      "  local result, err = summary.save_active(review_path, 'markdown')",
      "  if result then",
      "    write_diagnostics('saved', result)",
      "  else",
      "    write_diagnostics('error', { message = err and err.message or 'failed to save review' })",
      "  end",
      "end })",
      "",
      "vim.api.nvim_create_autocmd('VimEnter', {",
      "  once = true,",
      "  callback = function()",
      "    vim.defer_fn(function()",
      "      for _, buf in ipairs(vim.api.nvim_list_bufs()) do",
      "        if vim.api.nvim_buf_get_name(buf) == '' and not vim.bo[buf].modified then",
      "          pcall(vim.api.nvim_buf_delete, buf, { force = true })",
      "        end",
      "      end",
      "    end, 150)",
      "  end,",
      "})",
    ].join("\n") + "\n"
  );
}

export function buildContextInit(path: string, target: unknown): string {
  return [
    `local context_path = ${luaString(path)}`,
    `local target = ${luaJson(target)}`,
    "local agent_feedback = require('unified_review.agent_feedback')",
    "local result, err = agent_feedback.write_context(context_path, { target = target })",
    "if not result then",
    "  error(err and err.message or 'failed to write agent context')",
    "end",
    "vim.cmd('qa')",
  ].join("\n");
}

export function buildImportInit(
  feedbackPath: string,
  diagnosticsPath: string,
  target: unknown,
): string {
  return [
    `local feedback_path = ${luaString(feedbackPath)}`,
    `local diagnostics_path = ${luaString(diagnosticsPath)}`,
    `local target = ${luaJson(target)}`,
    "local function collect_messages()",
    "  local ok, result = pcall(vim.api.nvim_exec2, 'messages', { output = true })",
    "  return ok and result.output or ''",
    "end",
    "local function write(status, fields)",
    "  fields = fields or {}",
    "  fields.status = status",
    "  fields.v_errmsg = vim.v.errmsg",
    "  fields.messages = collect_messages()",
    "  pcall(vim.fn.writefile, { vim.json.encode(fields) }, diagnostics_path)",
    "end",
    "local ok, result_or_err = pcall(function()",
    "  local result, err = require('unified_review.agent_feedback').import_file(feedback_path, { target = target, refresh_ui = false })",
    "  if not result then error(err and err.message or 'failed to import agent feedback') end",
    "  return result",
    "end)",
    "if ok then write('imported', { result = result_or_err }) else write('error', { message = tostring(result_or_err) }) end",
    "vim.cmd(ok and 'qa' or 'cqa')",
  ].join("\n");
}

export function buildOpenInit(target: unknown): string {
  return [
    `local target = ${luaJson(target)}`,
    "vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()",
    "  vim.schedule(function() require('unified_review.session.manager').open_target(target, {}) end)",
    "end })",
  ].join("\n");
}
