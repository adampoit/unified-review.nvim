import { test } from "@microsoft/tui-test";
import assert from "node:assert/strict";
import { captureTerminal } from "../artifacts.js";
import { add, ctx, del, diffScenario, file } from "../diffDsl.js";
import {
  configureNvimTest,
  createRepoFromDiffScenario,
  occurrences,
} from "../helpers.js";
import {
  createInlineRangeComment,
  openReviewForRepo,
  waitForBuffer,
} from "./helpers.js";

configureNvimTest(test, { columns: 180, rows: 40 });

test.describe("range comments", () => {
  test("right-side ranges inside added blocks preserve spacer alignment", async ({
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

    const body = "INLINE_E2E_ADDED_RANGE_RIGHT_BODY";
    await createInlineRangeComment(terminal, body, {
      side: "right",
      startLine: 2,
      endLine: 3,
    });

    const marker = scenario.labels["shared_after:1"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - added range right");

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible range body ${body}`);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(
      bodyRow.indexOf(body) >= midpoint,
      `expected ${body} on the right side; got:\n${bodyRow}`,
    );
    assert.ok(
      bodyRow.indexOf("╱") < midpoint,
      `expected left-side slash spacer opposite the right-side range; got:\n${bodyRow}`,
    );
    assert.ok(
      rows.some((row) => occurrences(row, marker) >= 2),
      `expected shared marker ${marker} on both sides of one row; got:\n${rows.join("\n")}`,
    );
  });

  test("left-side ranges inside deleted blocks preserve spacer alignment", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
        ctx("before", ["SMALL_SHARED_BEFORE"]),
        del("small_deleted", [
          "SMALL_DELETED_TARGET_001",
          "SMALL_DELETED_TARGET_002",
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

    const body = "INLINE_E2E_DELETED_RANGE_LEFT_BODY";
    await createInlineRangeComment(terminal, body, {
      side: "left",
      startLine: 2,
      endLine: 3,
    });

    const marker = scenario.labels["shared_after:1"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - deleted range left");

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible range body ${body}`);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(
      bodyRow.indexOf(body) < midpoint,
      `expected ${body} on the left side; got:\n${bodyRow}`,
    );
    assert.ok(
      Array.from(bodyRow.matchAll(/╱/g), (match) => match.index || 0).some(
        (column) => column >= midpoint,
      ),
      `expected right-side slash spacer opposite the left-side range; got:\n${bodyRow}`,
    );
    assert.ok(
      rows.some((row) => occurrences(row, marker) >= 2),
      `expected shared marker ${marker} on both sides of one row; got:\n${rows.join("\n")}`,
    );
  });

  test("right-side ranges spanning context and changed lines preserve spacer alignment", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
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
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);

    const body = "INLINE_E2E_SPANNING_RANGE_RIGHT_BODY";
    await createInlineRangeComment(terminal, body, {
      side: "right",
      startLine: 1,
      endLine: 3,
    });

    const marker = scenario.labels["shared_after:2"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - spanning range right");

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible range body ${body}`);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
    assert.ok(rows.some((row) => occurrences(row, marker) >= 2));
  });

  test("left-side ranges spanning context and changed lines preserve spacer alignment", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
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
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);

    const body = "INLINE_E2E_SPANNING_RANGE_LEFT_BODY";
    await createInlineRangeComment(terminal, body, {
      side: "left",
      startLine: 1,
      endLine: 3,
    });

    const marker = scenario.labels["shared_after:2"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - spanning range left");

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible range body ${body}`);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) < midpoint, `got:\n${bodyRow}`);
    assert.ok(
      Array.from(bodyRow.matchAll(/╱/g), (match) => match.index || 0).some(
        (column) => column >= midpoint,
      ),
      `got:\n${bodyRow}`,
    );
    assert.ok(rows.some((row) => occurrences(row, marker) >= 2));
  });

  test("right-side ranges spanning adjacent hunks preserve later hunk alignment", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
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
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);

    const body = "INLINE_E2E_MULTI_HUNK_RANGE_RIGHT_BODY";
    await createInlineRangeComment(terminal, body, {
      side: "right",
      startLine: 14,
      endLine: 28,
    });

    const marker = scenario.labels["shared_after:1"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - multi hunk range right");

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible range body ${body}`);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
    assert.ok(rows.some((row) => occurrences(row, marker) >= 2));
  });
});
