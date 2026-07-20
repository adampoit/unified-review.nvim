import { expect } from "@microsoft/tui-test";
import type { Terminal } from "@microsoft/tui-test/lib/terminal/term.js";
import assert from "node:assert/strict";
import { add, ctx, del, diffScenario, file } from "../diffDsl.js";
import {
  createRepoFromDiffScenario,
  delay,
  luaString,
  runLua,
  waitForBuffer,
} from "../helpers.js";

export {
  luaString,
  occurrences,
  openReviewForRepo,
  reopenReviewForRepo,
  runLua,
  waitForBuffer,
} from "../helpers.js";

function createInlineRepo(ops: Parameters<typeof file>[1]) {
  return createRepoFromDiffScenario(
    diffScenario([file("src/inline.lua", ops)]),
  );
}

export function createAddedBlockInlineCommentRepo() {
  return createInlineRepo([
    ctx("prefix", 200),
    add("added_block", [
      "ADDED_BLOCK_INSERTED_001",
      "ADDED_BLOCK_TARGET_002",
      "ADDED_BLOCK_TARGET_003",
      "ADDED_BLOCK_TARGET_004",
      "ADDED_BLOCK_INSERTED_END",
      "ADDED_BLOCK_SPACER",
    ]),
    ctx("shared_after", [
      "SHARED_AFTER_ADDED_BLOCK",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
      "SHARED_AFTER_ADDED_BLOCK_RETURN",
    ]),
  ]);
}

export function createDeletedBlockInlineCommentRepo() {
  return createInlineRepo([
    ctx("prefix", 80),
    del("deleted_block", [
      "DELETED_BLOCK_REMOVED_001",
      "DELETED_BLOCK_TARGET_002",
      "DELETED_BLOCK_TARGET_003",
      "DELETED_BLOCK_TARGET_004",
      "DELETED_BLOCK_REMOVED_END",
      "DELETED_BLOCK_SPACER",
    ]),
    ctx("shared_after", [
      "SHARED_AFTER_DELETED_BLOCK",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
  ]);
}

export function createReplacementInlineCommentRepo() {
  return createInlineRepo([
    ctx("prefix", 120),
    ctx("replacement_block", ["REPLACEMENT_BLOCK"]),
    del("replacement_old", ["REPLACEMENT_OLD_VALUE", "REPLACEMENT_OLD_RETURN"]),
    add("replacement_new", [
      "REPLACEMENT_NEW_VALUE",
      "REPLACEMENT_NEW_EXTRA",
      "REPLACEMENT_NEW_RETURN",
    ]),
    ctx("shared_after", [
      "REPLACEMENT_BLOCK_END",
      "REPLACEMENT_SPACER",
      "SHARED_AFTER_REPLACEMENT_BLOCK",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
      "SHARED_AFTER_REPLACEMENT_BLOCK_RETURN",
    ]),
  ]);
}

export function createContextBeforeUnevenReplacementRepo() {
  return createInlineRepo([
    ctx("prefix", 286),
    del("tab_old", [
      "TAB_LABEL_AND_WINBAR_CONTEXT",
      "TAB_LABEL_STATUS_OLD_001",
      "TAB_LABEL_STATUS_OLD_002",
      "TAB_LABEL_LEFT_WINDOW_OLD_001",
      "TAB_LABEL_LEFT_WINDOW_OLD_002",
      "TAB_LABEL_LEFT_WINDOW_OLD_003",
      "TAB_LABEL_RIGHT_WINDOW_OLD_001",
      "TAB_LABEL_RIGHT_WINDOW_OLD_002",
      "TAB_LABEL_RIGHT_WINDOW_OLD_003",
      "TAB_LABEL_SPACER_OLD",
    ]),
    add("tab_new", [
      "TAB_LABEL_CONTEXT",
      "TAB_LABEL_STATUS_NEW_001",
      "TAB_LABEL_STATUS_NEW_002",
      "TAB_LABEL_SPACER_NEW",
    ]),
    ctx("schedule", [
      "SCHEDULE_SYNC_MARKER",
      "SCHEDULE_SYNC_BODY",
      "SCHEDULE_SYNC_END",
    ]),
  ]);
}

export function createSummaryInsertionBeforeCopyRepo() {
  return createInlineRepo([
    ctx("prefix", 27),
    add("summary_insert", 40),
    ctx("summary_copy", [
      "SUMMARY_COPY_MARKER",
      "SUMMARY_COPY_BODY",
      "SUMMARY_COPY_END",
    ]),
  ]);
}

export function createContextBeforePureDeletionRepo() {
  return createInlineRepo([
    ctx("prefix", 40),
    ctx("context_before", ["CONTEXT_BEFORE_PURE_DELETION"]),
    del("pure_deletion", [
      "PURE_DELETION_001",
      "PURE_DELETION_002",
      "PURE_DELETION_003",
    ]),
    ctx("shared_after", [
      "SHARED_AFTER_CONTEXT_DELETION",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
  ]);
}

export function createStartOfFileAdditionRepo() {
  return createInlineRepo([
    add("start_added", ["ADDED_AT_FILE_START", "ADDED_AT_FILE_START_AGAIN"]),
    ctx("shared_after", [
      "SHARED_AFTER_START_ADDITION",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
  ]);
}

export function createEndOfFileAdditionRepo() {
  return createInlineRepo([
    ctx("prefix", 20),
    ctx("shared_before", [
      "SHARED_BEFORE_EOF_ADDITION",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
    add("eof_added", ["EOF_ADDED_COMMENT_TARGET", "EOF_ADDED_RETURN"]),
  ]);
}

export function createEndOfFileDeletionRepo() {
  return createInlineRepo([
    ctx("prefix", 20),
    ctx("shared_before", [
      "SHARED_BEFORE_EOF_DELETION",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
    del("eof_deleted", ["EOF_DELETED_COMMENT_TARGET", "EOF_DELETED_RETURN"]),
  ]);
}

// Codediff intentionally renders whole-file additions/deletions as one-sided file views,
// so side-by-side inline spacer alignment is unsupported for those file statuses.
// See docs/codediff-limitations.md.

export function createSmallAddedBlockRepo() {
  return createInlineRepo([
    ctx("before", ["SMALL_SHARED_BEFORE"]),
    add("small_added", ["SMALL_ADDED_TARGET_001", "SMALL_ADDED_TARGET_002"]),
    ctx("shared_after", [
      "SHARED_AFTER_SMALL_ADDED",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
  ]);
}

export function createSmallDeletedBlockRepo() {
  return createInlineRepo([
    ctx("before", ["SMALL_SHARED_BEFORE"]),
    del("small_deleted", [
      "SMALL_DELETED_TARGET_001",
      "SMALL_DELETED_TARGET_002 = SMALL_DELETED_TARGET_001",
    ]),
    ctx("shared_after", [
      "SHARED_AFTER_SMALL_DELETED",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
  ]);
}

export function createEqualReplacementRepo() {
  return createInlineRepo([
    ctx("before", ["EQUAL_REPLACEMENT_BLOCK"]),
    del("equal_old", ["EQUAL_OLD_001", "EQUAL_OLD_002", "EQUAL_OLD_003"]),
    add("equal_new", ["EQUAL_NEW_001", "EQUAL_NEW_002", "EQUAL_NEW_003"]),
    ctx("shared_after", [
      "EQUAL_REPLACEMENT_END",
      "SHARED_AFTER_EQUAL_REPLACEMENT",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
  ]);
}

export function createLeftLongerReplacementRepo() {
  return createInlineRepo([
    ctx("before", ["LEFT_LONGER_REPLACEMENT_BLOCK"]),
    del("left_old", [
      "LEFT_LONGER_OLD_001",
      "LEFT_LONGER_OLD_002",
      "LEFT_LONGER_OLD_003",
    ]),
    add("left_new", ["LEFT_LONGER_NEW_001", "LEFT_LONGER_NEW_002"]),
    ctx("shared_after", [
      "LEFT_LONGER_REPLACEMENT_END",
      "SHARED_AFTER_LEFT_LONGER_REPLACEMENT",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
  ]);
}

export function createSmallReplacementRepo() {
  return createInlineRepo([
    ctx("before", ["SMALL_REPLACEMENT_BLOCK"]),
    del("small_old", [
      "SMALL_REPLACEMENT_OLD_001",
      "SMALL_REPLACEMENT_OLD_002",
    ]),
    add("small_new", [
      "SMALL_REPLACEMENT_NEW_001",
      "SMALL_REPLACEMENT_NEW_002",
      "SMALL_REPLACEMENT_NEW_003",
    ]),
    ctx("shared_after", [
      "SMALL_REPLACEMENT_END",
      "SHARED_AFTER_SMALL_REPLACEMENT",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
  ]);
}

export function createAdjacentHunksRepo() {
  return createInlineRepo([
    ctx("prefix", 12),
    ctx("first_shared", ["ADJACENT_FIRST_SHARED"]),
    add("first_added", ["ADJACENT_FIRST_ADDED_TARGET"]),
    ctx("between", 12),
    del("second_old", ["ADJACENT_SECOND_SHARED_OLD"]),
    add("second_new", [
      "ADJACENT_SECOND_SHARED_NEW",
      "ADJACENT_SECOND_ADDED_TARGET",
    ]),
    ctx("shared_after", [
      "SHARED_AFTER_ADJACENT_HUNKS",
      "SHARED_AFTER_BODY",
      "SHARED_AFTER_END",
    ]),
  ]);
}

export function createTwoFileRepo() {
  return createRepoFromDiffScenario(
    diffScenario([
      file("src/inline.lua", [
        ctx("inline_prefix", 20),
        add("inline_added", ["TWO_FILE_ADDED_TARGET"]),
        ctx("inline_shared", [
          "SHARED_AFTER_TWO_FILE_A",
          "SHARED_AFTER_BODY",
          "SHARED_AFTER_END",
        ]),
      ]),
      file("src/other.lua", [
        del("other_old", ["OTHER_BEFORE", "OTHER_BEFORE_RETURN"]),
        add("other_new", [
          "OTHER_AFTER",
          "OTHER_ADDED_TARGET",
          "OTHER_AFTER_RETURN",
        ]),
      ]),
    ]),
  );
}

export async function createInlineComment(
  terminal: Terminal,
  body: string,
  target: {
    side: "left" | "right";
    line: number;
    kind?: string;
    path?: string;
  },
) {
  const kind = target.kind || "line";
  const path = target.path || "src/inline.lua";
  terminal.write(
    `:lua require('unified_review.session.manager').create_comment(${luaString(body)}, { kind = ${luaString(kind)}, path = ${luaString(path)}, side = ${luaString(target.side)}, line = ${target.line} })\r`,
  );
  await delay(100);
  terminal.write("\r");
  const visibleNeedle = body.match(/\S+/)?.[0] || body;
  await expect(
    terminal.getByText(visibleNeedle, { strict: false }),
  ).toBeVisible();
}

export function scrollDiffSideToLine(
  terminal: Terminal,
  side: "left" | "right",
  line: number,
) {
  const winKey = side === "left" ? "left_window" : "right_window";
  terminal.write(
    `:lua local s=require('unified_review.session.manager').active(); vim.api.nvim_set_current_win(s.ui.${winKey}); vim.api.nvim_win_set_cursor(s.ui.${winKey}, {${line}, 0})\r`,
  );
}

export async function createInlineCommentThroughEditor(
  terminal: Terminal,
  body: string,
  target: { side: "left" | "right"; line: number },
) {
  const winKey = target.side === "left" ? "left_window" : "right_window";
  runLua(
    terminal,
    `local s=require('unified_review.session.manager').active(); vim.api.nvim_set_current_win(s.ui.${winKey}); vim.api.nvim_win_set_cursor(s.ui.${winKey}, {${target.line}, 0}); vim.cmd('UnifiedReview comment')`,
  );
  await expect(
    terminal.getByText("<C-s> save · Esc cancel", { strict: false }),
  ).toBeVisible();
  await delay(50);
  terminal.write(body);
  await expect(terminal.getByText(body, { strict: false })).toBeVisible();
  terminal.write("\u001c\u000e");
  terminal.write(":write\r");
  await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(body)) &&
      !visibleRows.some((row) => row.includes("Comment ·")),
  );
}

export async function createInlineRangeComment(
  terminal: Terminal,
  body: string,
  target: {
    side: "left" | "right";
    startLine: number;
    endLine: number;
    path?: string;
  },
) {
  const path = target.path || "src/inline.lua";
  runLua(
    terminal,
    `require('unified_review.session.manager').create_comment(${luaString(body)}, { kind = 'range', path = ${luaString(path)}, start_side = ${luaString(target.side)}, start_line = ${target.startLine}, side = ${luaString(target.side)}, line = ${target.endLine} })`,
  );
  await delay(100);
  terminal.write("\r");
  await expect(terminal.getByText(body, { strict: false })).toBeVisible();
}

export function selectFileByPath(terminal: Terminal, path: string) {
  runLua(
    terminal,
    `local s=require('unified_review.session.manager').active(); for i,f in ipairs(s.files or {}) do if f.path == ${luaString(path)} or f.old_path == ${luaString(path)} then require('unified_review.session.selection').select_file(s, i); require('unified_review.ui.diff_view').render(s); break end end`,
  );
}

export async function assertInlineVisualRowsAligned(
  terminal: Terminal,
  body: string,
  side: "left" | "right",
) {
  const script = `
local body = ${luaString(body)}
local side = ${luaString(side)}
local session = require('unified_review.session.manager').active()
assert(session and session.ui, 'no active review session')
local namespaces = vim.api.nvim_get_namespaces()
local ns_inline = namespaces.unified_review_inline_virt
local ok_highlights, highlights = pcall(require, 'codediff.ui.highlights')
local ns_filler = ok_highlights and highlights.ns_filler or nil
local ns_highlight = ok_highlights and highlights.ns_highlight or nil
local function buf_for(which)
  return which == 'left' and session.ui.left_buffer or session.ui.right_buffer
end
local function line_text(lines)
  local out = ''
  for _, line in ipairs(lines or {}) do
    for _, chunk in ipairs(line) do
      out = out .. (chunk[1] or '')
    end
    out = out .. '\\n'
  end
  return out
end
local function collect_marks(buf, ns_list)
  local marks = {}
  for _, ns in ipairs(ns_list or {}) do
    if ns then
      for _, raw in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        local details = raw[4] or {}
        if details.virt_lines then
          table.insert(marks, {
            row = raw[2],
            above = details.virt_lines_above == true,
            count = #details.virt_lines,
            text = line_text(details.virt_lines),
          })
        end
      end
    end
  end
  table.sort(marks, function(a, b)
    if a.row == b.row then
      return a.above and not b.above
    end
    return a.row < b.row
  end)
  return marks
end
local function visual_before(buf, row)
  local visual = row
  for _, mark in ipairs(collect_marks(buf, { ns_filler, ns_highlight, ns_inline })) do
    if mark.row < row or (mark.row == row and mark.above) then
      visual = visual + mark.count
    end
  end
  return visual
end
local function visual_start(buf, mark)
  if mark.above then
    return visual_before(buf, mark.row) - mark.count
  end
  return visual_before(buf, mark.row) + 1
end
local target_buf = buf_for(side)
local target_mark
for _, mark in ipairs(collect_marks(target_buf, { ns_inline, ns_filler })) do
  if mark.text:find(body, 1, true) then
    target_mark = mark
    break
  end
end
assert(target_mark, 'comment body extmark not found: ' .. body)
local target_visual = visual_start(target_buf, target_mark)
local other_buf = buf_for(side == 'left' and 'right' or 'left')
local covered = false
for _, mark in ipairs(collect_marks(other_buf, { ns_inline, ns_filler })) do
  local start_row = visual_start(other_buf, mark)
  local end_row = start_row + mark.count - 1
  if start_row <= target_visual and target_visual <= end_row and mark.text:find('╱', 1, true) then
    covered = true
    break
  end
end
assert(covered, string.format('no opposite spacer covers visual row %d', target_visual))
`;
  terminal.write(
    `:lua local f=loadstring(${luaString(script)}); local ok,err=pcall(f); vim.g.ur_e2e_visual_alignment_result = ok and 'UR_VISUAL_ALIGNMENT_OK' or ('UR_VISUAL_ALIGNMENT_ERR: '..tostring(err))\r`,
  );
  terminal.write(":echo g:ur_e2e_visual_alignment_result\r");
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes("UR_VISUAL_ALIGNMENT_OK")) ||
      visibleRows.some((row) => row.includes("UR_VISUAL_ALIGNMENT_ERR")),
  );
  assert.ok(
    rows.some((row) => row.includes("UR_VISUAL_ALIGNMENT_OK")),
    `expected exact inline visual alignment for ${body}; got:\n${rows.join("\n")}`,
  );
}
