import { expect, test } from "@microsoft/tui-test";
import assert from "node:assert/strict";
import { captureTerminal } from "../artifacts.js";
import { add, ctx, del, diffScenario, file } from "../diffDsl.js";
import {
  configureNvimTest,
  createRepoFromDiffScenario,
  occurrences,
} from "../helpers.js";
import {
  createInlineCommentThroughEditor,
  openReviewForRepo,
  runLua,
  waitForBuffer,
} from "./helpers.js";

configureNvimTest(test, { columns: 180, rows: 40 });

test.describe("comment editor workflow inline rendering", () => {
  test("comment editor is anchored below its target with an opposite-side spacer", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
        ctx("before", ["INLINE_EDITOR_SHARED_BEFORE"]),
        add("target", ["INLINE_EDITOR_TARGET", "INLINE_EDITOR_AFTER"]),
        ctx("shared_after", ["INLINE_EDITOR_SHARED_AFTER"]),
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);
    await expect(
      terminal.getByText("INLINE_EDITOR_TARGET", { strict: false }),
    ).toBeVisible();

    runLua(
      terminal,
      "local s=require('unified_review.session.manager').active(); vim.api.nvim_set_current_win(s.ui.right_window); vim.api.nvim_win_set_cursor(s.ui.right_window, {2, 0}); vim.cmd('UnifiedReview comment')",
    );
    await expect(
      terminal.getByText("<C-s> save · Esc cancel", { strict: false }),
    ).toBeVisible();

    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes("INLINE_EDITOR_TARGET")) &&
        visibleRows.some(
          (row) => row.includes("Comment ·") && row.includes("╱"),
        ),
    );
    captureTerminal(terminal, "inline comment editor - anchored to diff");

    const targetRow = rows.findIndex((row) =>
      row.includes("INLINE_EDITOR_TARGET"),
    );
    const editorRow = rows.findIndex((row) => row.includes("Comment ·"));
    assert.ok(editorRow > targetRow, "expected the editor below its target");
    assert.ok(
      rows[editorRow].includes("╱"),
      "expected an aligned spacer opposite the editor",
    );

    terminal.write("\u001b");
  });

  test("saving from insert mode returns focus to the diff in normal mode", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
        ctx("before", ["INSERT_MODE_SHARED_BEFORE"]),
        add("target", ["INSERT_MODE_TARGET", "INSERT_MODE_AFTER"]),
        ctx("shared_after", ["INSERT_MODE_SHARED_AFTER"]),
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);
    await expect(
      terminal.getByText("INSERT_MODE_TARGET", { strict: false }),
    ).toBeVisible();

    runLua(
      terminal,
      "local s=require('unified_review.session.manager').active(); vim.api.nvim_set_current_win(s.ui.right_window); vim.api.nvim_win_set_cursor(s.ui.right_window, {2, 0}); vim.cmd('UnifiedReview comment')",
    );
    await expect(
      terminal.getByText("<C-s> save · Esc cancel", { strict: false }),
    ).toBeVisible();

    const body = "INSERT_MODE_SAVE_BODY";
    terminal.write(body);
    await expect(terminal.getByText(body, { strict: false })).toBeVisible();
    terminal.write("\u0013");

    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body)) &&
        visibleRows.some((row) => row.includes("right L2")) &&
        !visibleRows.some((row) => row.includes("-- INSERT --")) &&
        !visibleRows.some((row) => row.includes("Comment ·")),
    );
    assert.ok(
      rows.some((row) => row.includes("INSERT_MODE_AFTER")),
      "expected focus to return to the diff after saving",
    );
  });

  test("right-side comments created through :UnifiedReview comment render inline with left spacers", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
        ctx("before", ["SMALL_SHARED_BEFORE"]),
        add("small_added", [
          "SMALL_ADDED_TARGET_001",
          "SMALL_ADDED_TARGET_002",
        ]),
        ctx("shared_after", [
          "SHARED_AFTER_SMALL_ADDED",
          "SHARED_AFTER_BODY",
          "SHARED_AFTER_END",
        ]),
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);

    const target = scenario.labels["small_added:1"].text;
    const marker = scenario.labels["shared_after:1"].text;
    await expect(terminal.getByText(target, { strict: false })).toBeVisible();
    const body = "INLINE_E2E_EDITOR_RIGHT_BODY";

    await createInlineCommentThroughEditor(terminal, body, {
      side: "right",
      line: 2,
    });

    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - editor right side");

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1, `expected target row ${target}`);
    assert.ok(
      rows[targetRow + 1]?.includes("right L2"),
      `expected comment header "right L2" immediately after ${target}; got:\n${rows
        .slice(Math.max(0, targetRow - 2), targetRow + 6)
        .join("\n")}`,
    );

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected exactly one visible body row for ${body}`);
    assert.equal(
      occurrences(rows.join("\n"), body),
      1,
      `expected exactly one visible inline body ${body}`,
    );
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(
      bodyRow.indexOf(body) >= midpoint,
      `expected ${body} on the right side; got:\n${bodyRow}`,
    );
    assert.ok(
      bodyRow.indexOf("╱") < midpoint,
      `expected an opposite slash spacer on the left side; got:\n${bodyRow}`,
    );

    const markerRow = rows.find((row) => occurrences(row, marker) >= 2);
    assert.ok(
      markerRow,
      `expected shared marker ${marker} to appear on both sides of one row; got:\n${rows.join("\n")}`,
    );
  });

  test("left-side comments created through :UnifiedReview comment render inline with right spacers", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
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
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);

    const target = scenario.labels["small_deleted:1"].text;
    const marker = scenario.labels["shared_after:1"].text;
    await expect(terminal.getByText(target, { strict: false })).toBeVisible();
    const body = "INLINE_E2E_EDITOR_LEFT_BODY";

    await createInlineCommentThroughEditor(terminal, body, {
      side: "left",
      line: 2,
    });

    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - editor left side");

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1, `expected target row ${target}`);
    assert.ok(
      rows[targetRow + 1]?.includes("left L2"),
      `expected comment header "left L2" immediately after ${target}; got:\n${rows
        .slice(Math.max(0, targetRow - 2), targetRow + 6)
        .join("\n")}`,
    );

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected exactly one visible body row for ${body}`);
    assert.equal(
      occurrences(rows.join("\n"), body),
      1,
      `expected exactly one visible inline body ${body}`,
    );
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(
      bodyRow.indexOf(body) < midpoint,
      `expected ${body} on the left side; got:\n${bodyRow}`,
    );
    assert.ok(
      Array.from(bodyRow.matchAll(/╱/g), (match) => match.index || 0).some(
        (column) => column >= midpoint,
      ),
      `expected an opposite slash spacer on the right side; got:\n${bodyRow}`,
    );

    const markerRow = rows.find((row) => occurrences(row, marker) >= 2);
    assert.ok(
      markerRow,
      `expected shared marker ${marker} to appear on both sides of one row; got:\n${rows.join("\n")}`,
    );
  });
});
