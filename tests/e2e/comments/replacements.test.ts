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
  createInlineComment,
  openReviewForRepo,
  waitForBuffer,
} from "./helpers.js";

configureNvimTest(test, { columns: 180, rows: 40 });

test.describe("replacement comments", () => {
  test("right-side comments on replacement-only lines get opposite-side slash rows", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
        ctx("prefix", 120),
        ctx("replacement_block", ["REPLACEMENT_BLOCK"]),
        del("replacement_old", [
          "REPLACEMENT_OLD_VALUE",
          "REPLACEMENT_OLD_RETURN",
        ]),
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
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);
    await expect(
      terminal.getByText("REPLACEMENT_BLOCK", { strict: false }),
    ).toBeVisible();

    const body = "INLINE_E2E_RIGHT_REPLACEMENT_BODY";
    await createInlineComment(terminal, body, { side: "right", line: 123 });

    const target = scenario.labels["replacement_new:2"].text;
    const marker = scenario.labels["shared_after:3"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => row.includes(target)) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(
      terminal,
      "inline comments - right replacement target line",
    );

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1, `expected target row ${target}`);
    assert.ok(
      rows[targetRow + 1]?.includes("right L123"),
      `expected comment header "right L123" immediately after ${target}; got:\n${rows
        .slice(Math.max(0, targetRow - 2), targetRow + 6)
        .join("\n")}`,
    );
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
    assert.ok(rows.some((row) => occurrences(row, marker) >= 2));
  });

  test("left-side comments on replacement lines get opposite-side slash rows", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
        ctx("prefix", 120),
        ctx("replacement_block", ["REPLACEMENT_BLOCK"]),
        del("replacement_old", [
          "REPLACEMENT_OLD_VALUE",
          "REPLACEMENT_OLD_RETURN",
        ]),
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
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);
    await expect(
      terminal.getByText("REPLACEMENT_BLOCK", { strict: false }),
    ).toBeVisible();

    const body = "INLINE_E2E_LEFT_REPLACEMENT_BODY";
    await createInlineComment(terminal, body, { side: "left", line: 122 });

    const target = scenario.labels["replacement_old:1"].text;
    const marker = scenario.labels["shared_after:3"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => row.includes(target)) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(
      terminal,
      "inline comments - left replacement paired spacer rows",
    );

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1, `expected target row ${target}`);
    assert.ok(
      rows[targetRow + 1]?.includes("left L122"),
      `expected comment header "left L122" immediately after ${target}; got:\n${rows
        .slice(Math.max(0, targetRow - 2), targetRow + 6)
        .join("\n")}`,
    );
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
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

  test("right-side comments in equal-length replacements", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
        ctx("before", ["EQUAL_REPLACEMENT_BLOCK"]),
        del("equal_old", ["EQUAL_OLD_001", "EQUAL_OLD_002", "EQUAL_OLD_003"]),
        add("equal_new", ["EQUAL_NEW_001", "EQUAL_NEW_002", "EQUAL_NEW_003"]),
        ctx("shared_after", [
          "EQUAL_REPLACEMENT_END",
          "SHARED_AFTER_EQUAL_REPLACEMENT",
          "SHARED_AFTER_BODY",
          "SHARED_AFTER_END",
        ]),
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);

    const body = "INLINE_E2E_EQUAL_REPLACEMENT_RIGHT";
    await createInlineComment(terminal, body, { side: "right", line: 2 });

    const marker = scenario.labels["shared_after:2"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - equal replacement right");

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
    assert.ok(rows.some((row) => occurrences(row, marker) >= 2));
  });

  test("left-side comments in equal-length replacements", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
        ctx("before", ["EQUAL_REPLACEMENT_BLOCK"]),
        del("equal_old", ["EQUAL_OLD_001", "EQUAL_OLD_002", "EQUAL_OLD_003"]),
        add("equal_new", ["EQUAL_NEW_001", "EQUAL_NEW_002", "EQUAL_NEW_003"]),
        ctx("shared_after", [
          "EQUAL_REPLACEMENT_END",
          "SHARED_AFTER_EQUAL_REPLACEMENT",
          "SHARED_AFTER_BODY",
          "SHARED_AFTER_END",
        ]),
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);

    const body = "INLINE_E2E_EQUAL_REPLACEMENT_LEFT";
    await createInlineComment(terminal, body, { side: "left", line: 2 });

    const marker = scenario.labels["shared_after:2"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - equal replacement left");

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
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

  test("left-side comments on left-only replacement rows", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
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
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);

    const body = "INLINE_E2E_LEFT_LONGER_REPLACEMENT_LEFT_ONLY";
    await createInlineComment(terminal, body, { side: "left", line: 3 });

    const marker = scenario.labels["shared_after:2"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(
      terminal,
      "inline comments - left longer replacement left only",
    );

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
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

  test("right-side comments in left-longer replacements", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
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
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);

    const body = "INLINE_E2E_LEFT_LONGER_REPLACEMENT_RIGHT";
    await createInlineComment(terminal, body, { side: "right", line: 2 });

    const marker = scenario.labels["shared_after:2"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(
      terminal,
      "inline comments - left longer replacement right",
    );

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
    assert.ok(rows.some((row) => occurrences(row, marker) >= 2));
  });
});

test("comments on both sides of the same replacement row preserve downstream alignment", async ({
  terminal,
}) => {
  const scenario = diffScenario([
    file("src/inline.lua", [
      ctx("prefix", 120),
      ctx("replacement_block", ["REPLACEMENT_BLOCK"]),
      del("replacement_old", [
        "REPLACEMENT_OLD_VALUE",
        "REPLACEMENT_OLD_RETURN",
      ]),
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
    ]),
  ]);
  const repo = createRepoFromDiffScenario(scenario);
  await openReviewForRepo(terminal, repo);

  const leftBody = "INLINE_E2E_BOTH_SIDES_LEFT_BODY";
  const rightBody = "INLINE_E2E_BOTH_SIDES_RIGHT_BODY";
  await createInlineComment(terminal, leftBody, { side: "left", line: 122 });
  await createInlineComment(terminal, rightBody, { side: "right", line: 122 });

  const marker = scenario.labels["shared_after:3"].text;
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(leftBody)) &&
      visibleRows.some((row) => row.includes(rightBody)) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(
    terminal,
    "inline comments - both sides same replacement row",
  );

  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:\n${rows.join("\n")}`,
  );
});
