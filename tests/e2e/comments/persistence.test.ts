import { expect, test } from "@microsoft/tui-test";
import assert from "node:assert/strict";
import { captureTerminal } from "../artifacts.js";
import { configureNvimTest } from "../helpers.js";
import {
  createAddedBlockInlineCommentRepo,
  createInlineComment,
  createInlineRangeComment,
  createSmallAddedBlockRepo,
  createTwoFileRepo,
  luaString,
  occurrences,
  openReviewForRepo,
  reopenReviewForRepo,
  runLua,
  selectFileByPath,
  waitForBuffer,
} from "./helpers.js";

configureNvimTest(test, { columns: 180, rows: 40 });

test("persisted inline comments remain aligned after closing and reopening the review", async ({
  terminal,
}) => {
  const repo = createAddedBlockInlineCommentRepo();
  await openReviewForRepo(terminal, repo);
  const body = "INLINE_E2E_PERSISTED_AFTER_REOPEN_BODY";
  await createInlineComment(terminal, body, { side: "right", line: 202 });

  await reopenReviewForRepo(terminal, repo);
  await expect(terminal.getByText(body, { strict: false })).toBeVisible();

  const marker = "SHARED_AFTER_ADDED_BLOCK";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(terminal, "inline comments - persisted after reopen");
  const bodyRow = rows.find((row) => row.includes(body));
  assert.ok(bodyRow, `expected visible body row ${body}`);
  assert.equal(occurrences(rows.join("\n"), body), 1);
  const midpoint = Math.floor(bodyRow.length / 2);
  assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
  assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:\n${rows.join("\n")}`,
  );
});

test("persisted range comments keep replies and resolved/exported state after reopening", async ({
  terminal,
}) => {
  const repo = createSmallAddedBlockRepo();
  await openReviewForRepo(terminal, repo);
  const body = "INLINE_E2E_PERSISTED_RANGE_BODY";
  const replyBody = "INLINE_E2E_PERSISTED_RANGE_REPLY";
  await createInlineRangeComment(terminal, body, {
    side: "right",
    startLine: 2,
    endLine: 3,
  });
  runLua(
    terminal,
    `local m=require('unified_review.session.manager'); local t=(m.list_threads() or {})[1]; m.reply(t.id, ${luaString(replyBody)}); m.resolve_thread(t.id); m.toggle_thread_export(t.id)`,
  );

  await reopenReviewForRepo(terminal, repo);
  await expect(terminal.getByText(body, { strict: false })).toBeVisible();
  await expect(terminal.getByText(replyBody, { strict: false })).toBeVisible();

  const marker = "SHARED_AFTER_SMALL_ADDED";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
      visibleRows.some((row) => row.includes(replyBody) && row.includes("╱")) &&
      visibleRows.some((row) => row.includes("resolved")) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(
    terminal,
    "inline comments - persisted range reply resolved exported",
  );
  for (const visibleBody of [body, replyBody]) {
    const bodyRow = rows.find((row) => row.includes(visibleBody));
    assert.ok(bodyRow, `expected visible body row ${visibleBody}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(visibleBody) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  }
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:\n${rows.join("\n")}`,
  );
});

test("deleting a draft removes its inline block and restores downstream alignment", async ({
  terminal,
}) => {
  const repo = createSmallAddedBlockRepo();
  await openReviewForRepo(terminal, repo);
  const body = "INLINE_E2E_DELETE_CLEANUP_BODY";
  await createInlineComment(terminal, body, { side: "right", line: 2 });
  await expect(terminal.getByText(body, { strict: false })).toBeVisible();

  runLua(
    terminal,
    "local m=require('unified_review.session.manager'); local t=(m.list_threads() or {})[1]; m.delete_draft(t.comments[1].id)",
  );
  await expect(terminal.getByText(body, { strict: false })).not.toBeVisible();
  runLua(
    terminal,
    "print('INLINE_E2E_THREAD_COUNT_' .. #(require('unified_review.session.manager').list_threads() or {}))",
  );
  await expect(
    terminal.getByText("INLINE_E2E_THREAD_COUNT_0", { strict: false }),
  ).toBeVisible();

  const marker = "SHARED_AFTER_SMALL_ADDED";
  const rows = await waitForBuffer(terminal, (visibleRows) =>
    visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(terminal, "inline comments - delete cleanup");
  assert.equal(
    occurrences(rows.join("\n"), body),
    0,
    `expected deleted body to be absent; got:\n${rows.join("\n")}`,
  );
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:\n${rows.join("\n")}`,
  );
});

test("inline comments remain aligned after switching files and returning", async ({
  terminal,
}) => {
  const repo = createTwoFileRepo();
  await openReviewForRepo(terminal, repo);
  selectFileByPath(terminal, "src/inline.lua");
  await expect(
    terminal.getByText("TWO_FILE_ADDED_TARGET", { strict: false }),
  ).toBeVisible();
  const body = "INLINE_E2E_AFTER_FILE_SWITCH_BODY";
  await createInlineComment(terminal, body, { side: "right", line: 21 });

  selectFileByPath(terminal, "src/other.lua");
  await expect(
    terminal.getByText("OTHER_ADDED_TARGET", { strict: false }),
  ).toBeVisible();
  selectFileByPath(terminal, "src/inline.lua");
  await expect(terminal.getByText(body, { strict: false })).toBeVisible();

  const marker = "SHARED_AFTER_TWO_FILE_A";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(terminal, "inline comments - after file switch");
  const bodyRow = rows.find((row) => row.includes(body));
  assert.ok(bodyRow, `expected visible body row ${body}`);
  assert.equal(occurrences(rows.join("\n"), body), 1);
  const midpoint = Math.floor(bodyRow.length / 2);
  assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
  assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:\n${rows.join("\n")}`,
  );
});

test("resolved and exported thread markers preserve spacer alignment", async ({
  terminal,
}) => {
  const repo = createAddedBlockInlineCommentRepo();
  await openReviewForRepo(terminal, repo);
  const body = "INLINE_E2E_RESOLVED_EXPORTED_BODY";
  await createInlineComment(terminal, body, { side: "right", line: 202 });
  runLua(
    terminal,
    "local m=require('unified_review.session.manager'); local t=(m.list_threads() or {})[1]; m.resolve_thread(t.id); m.toggle_thread_export(t.id)",
  );

  const marker = "SHARED_AFTER_ADDED_BLOCK";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
      visibleRows.some((row) => row.includes("resolved")) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(terminal, "inline comments - resolved exported state");
  const bodyRow = rows.find((row) => row.includes(body));
  assert.ok(bodyRow, `expected visible body row ${body}`);
  assert.equal(occurrences(rows.join("\n"), body), 1);
  const midpoint = Math.floor(bodyRow.length / 2);
  assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
  assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:\n${rows.join("\n")}`,
  );
});
