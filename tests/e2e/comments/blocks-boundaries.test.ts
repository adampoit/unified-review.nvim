import { expect, test } from "@microsoft/tui-test";
import assert from "node:assert/strict";
import { captureTerminal } from "../artifacts.js";
import { add, ctx, del, diffScenario, file } from "../diffDsl.js";
import { configureNvimTest, createRepoFromDiffScenario } from "../helpers.js";
import {
  assertInlineVisualRowsAligned,
  createAddedBlockInlineCommentRepo,
  createAdjacentHunksRepo,
  createContextBeforePureDeletionRepo,
  createContextBeforeUnevenReplacementRepo,
  createInlineComment,
  createSmallAddedBlockRepo,
  createSummaryInsertionBeforeCopyRepo,
  luaString,
  occurrences,
  openReviewForRepo,
  runLua,
  scrollDiffSideToLine,
  waitForBuffer,
} from "./helpers.js";

configureNvimTest(test, { columns: 180, rows: 40 });

test.describe("one-sided block comments", () => {
  test("right-side comments expose an opposite spacer on the same computed visual row", async ({
    terminal,
  }) => {
    const repo = createSmallAddedBlockRepo();
    await openReviewForRepo(terminal, repo);
    const body = "INLINE_E2E_EXACT_VISUAL_ROW_RIGHT";
    await createInlineComment(terminal, body, { side: "right", line: 2 });

    await assertInlineVisualRowsAligned(terminal, body, "right");
  });

  test("right-side comments inside added blocks get opposite-side slash rows", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
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
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);
    await expect(
      terminal.getByText("ADDED_BLOCK_INSERTED_001", { strict: false }),
    ).toBeVisible();

    const body = "INLINE_E2E_ADDED_BLOCK_BODY";
    await createInlineComment(terminal, body, { side: "right", line: 202 });

    const target = scenario.labels["added_block:2"].text;
    const marker = scenario.labels["shared_after:1"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(
      terminal,
      "inline comments - added block paired spacer rows",
    );

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1, `expected target row ${target}`);
    assert.ok(rows[targetRow + 1]?.includes("right L202"));
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
    assert.ok(rows.some((row) => occurrences(row, marker) >= 2));
  });

  test("left-side comments inside deleted blocks get opposite-side slash rows", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
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
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);
    await expect(
      terminal.getByText("DELETED_BLOCK_REMOVED_001", { strict: false }),
    ).toBeVisible();

    const body = "INLINE_E2E_DELETED_BLOCK_BODY";
    await createInlineComment(terminal, body, { side: "left", line: 82 });

    const target = scenario.labels["deleted_block:2"].text;
    const marker = scenario.labels["shared_after:1"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(
      terminal,
      "inline comments - deleted block paired spacer rows",
    );

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1, `expected target row ${target}`);
    assert.ok(rows[targetRow + 1]?.includes("left L82"));
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
});

test.describe("hunk-boundary comments", () => {
  test("right-side comments on the first added line", async ({ terminal }) => {
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

    const body = "INLINE_E2E_BOUNDARY_RIGHT_FIRST_ADDED";
    await createInlineComment(terminal, body, { side: "right", line: 2 });

    const target = scenario.labels["small_added:1"].text;
    const marker = scenario.labels["shared_after:1"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - boundary right first added");

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1);
    assert.ok(rows[targetRow + 1]?.includes("right L2"));
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
    assert.ok(rows.some((row) => occurrences(row, marker) >= 2));
  });

  test("right-side comments on the last added line", async ({ terminal }) => {
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

    const body = "INLINE_E2E_BOUNDARY_RIGHT_LAST_ADDED";
    await createInlineComment(terminal, body, { side: "right", line: 3 });

    const target = scenario.labels["small_added:2"].text;
    const marker = scenario.labels["shared_after:1"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - boundary right last added");

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1);
    assert.ok(rows[targetRow + 1]?.includes("right L3"));
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
    assert.ok(rows.some((row) => occurrences(row, marker) >= 2));
  });

  test("left-side comments on the first deleted line", async ({ terminal }) => {
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

    const body = "INLINE_E2E_BOUNDARY_LEFT_FIRST_DELETED";
    await createInlineComment(terminal, body, { side: "left", line: 2 });

    const target = scenario.labels["small_deleted:1"].text;
    const marker = scenario.labels["shared_after:1"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - boundary left first deleted");

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1);
    assert.ok(rows[targetRow + 1]?.includes("left L2"));
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow);
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

  test("left-side comments on the last deleted line", async ({ terminal }) => {
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

    const body = "INLINE_E2E_BOUNDARY_LEFT_LAST_DELETED";
    await createInlineComment(terminal, body, { side: "left", line: 3 });

    const target = scenario.labels["small_deleted:2"].text;
    const marker = scenario.labels["shared_after:1"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - boundary left last deleted");

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1);
    assert.ok(rows[targetRow + 1]?.includes("left L3"));
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow);
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

  test("right-side context comments immediately after additions", async ({
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

    const body = "INLINE_E2E_BOUNDARY_RIGHT_CONTEXT_AFTER_ADDED";
    await createInlineComment(terminal, body, { side: "right", line: 4 });

    const target = scenario.labels["shared_after:1"].text;
    const marker = scenario.labels["shared_after:2"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(
      terminal,
      "inline comments - boundary right context after added",
    );

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1);
    assert.ok(rows[targetRow + 1]?.includes("right L4"));
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
    assert.ok(rows.some((row) => occurrences(row, marker) >= 2));
  });

  test("left-side context comments immediately after deletions", async ({
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

    const body = "INLINE_E2E_BOUNDARY_LEFT_CONTEXT_AFTER_DELETED";
    await createInlineComment(terminal, body, { side: "left", line: 4 });

    const target = scenario.labels["shared_after:1"].text;
    const marker = scenario.labels["shared_after:2"].text;
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
        visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(
      terminal,
      "inline comments - boundary left context after deleted",
    );

    const targetRow = rows.findIndex((row) => row.includes(target));
    assert.notEqual(targetRow, -1);
    assert.ok(rows[targetRow + 1]?.includes("left L4"));
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow);
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
});

test("multiple comments at different offsets in one added block keep the shared tail aligned", async ({
  terminal,
}) => {
  const repo = createAddedBlockInlineCommentRepo();
  await openReviewForRepo(terminal, repo);
  await expect(
    terminal.getByText("ADDED_BLOCK_INSERTED_001", {
      strict: false,
    }),
  ).toBeVisible();

  const firstBody = "INLINE_E2E_ADDED_FIRST_OFFSET";
  const secondBody = "INLINE_E2E_ADDED_SECOND_OFFSET";
  await createInlineComment(terminal, firstBody, { side: "right", line: 201 });
  await createInlineComment(terminal, secondBody, { side: "right", line: 204 });

  const marker = "SHARED_AFTER_ADDED_BLOCK";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(firstBody) && row.includes("╱")) &&
      visibleRows.some(
        (row) => row.includes(secondBody) && row.includes("╱"),
      ) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(terminal, "inline comments - multiple added block offsets");

  {
    const bodyRow = rows.find((row) => row.includes(firstBody));
    assert.ok(bodyRow, `expected visible body row ${firstBody}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(firstBody) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  }
  {
    const bodyRow = rows.find((row) => row.includes(secondBody));
    assert.ok(bodyRow, `expected visible body row ${secondBody}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(secondBody) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  }
  assert.equal(occurrences(rows.join("\n"), firstBody), 1);
  assert.equal(occurrences(rows.join("\n"), secondBody), 1);
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:
${rows.join("\n")}`,
  );
});

test("context-line comments before an uneven replacement get same-row slash fillers", async ({
  terminal,
}) => {
  const repo = createContextBeforeUnevenReplacementRepo();
  await openReviewForRepo(terminal, repo);
  await expect(
    terminal.getByText("TAB_LABEL_CONTEXT", { strict: false }),
  ).toBeVisible();

  const body = "INLINE_E2E_CONTEXT_BEFORE_REPLACEMENT_BODY";
  await createInlineComment(terminal, body, { side: "right", line: 287 });

  const marker = "SCHEDULE_SYNC_MARKER";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(
    terminal,
    "inline comments - context before uneven replacement",
  );

  {
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  }
  assert.equal(occurrences(rows.join("\n"), body), 1);
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:
${rows.join("\n")}`,
  );
});

test("comments inside large one-sided insertions preserve downstream side-by-side alignment", async ({
  terminal,
}) => {
  const repo = createSummaryInsertionBeforeCopyRepo();
  await openReviewForRepo(terminal, repo);
  await expect(
    terminal.getByText("ADD_SUMMARY_INSERT_001", { strict: false }),
  ).toBeVisible();

  const body = "INLINE_E2E_SUMMARY_INSERTION_BODY";
  await createInlineComment(terminal, body, { side: "right", line: 31 });

  const bodyRows = await waitForBuffer(terminal, (visibleRows) =>
    visibleRows.some((row) => row.includes(body) && row.includes("╱")),
  );
  {
    const bodyRow = bodyRows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  }
  assert.equal(occurrences(bodyRows.join("\n"), body), 1);

  const marker = "SUMMARY_COPY_MARKER";
  scrollDiffSideToLine(terminal, "right", 68);
  const markerRows = await waitForBuffer(terminal, (visibleRows) =>
    visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(terminal, "inline comments - large insertion before M.copy");

  assert.ok(
    markerRows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:
${markerRows.join("\n")}`,
  );
});

test("context-line comments before a pure deletion splice into target-side codediff filler", async ({
  terminal,
}) => {
  const repo = createContextBeforePureDeletionRepo();
  await openReviewForRepo(terminal, repo);
  await expect(
    terminal.getByText("CONTEXT_BEFORE_PURE_DELETION", { strict: false }),
  ).toBeVisible();

  const body = "INLINE_E2E_CONTEXT_BEFORE_DELETION_BODY";
  await createInlineComment(terminal, body, { side: "right", line: 41 });

  const marker = "SHARED_AFTER_CONTEXT_DELETION";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(terminal, "inline comments - CONTEXT_BEFORE_PURE_DELETION");

  {
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  }
  assert.equal(occurrences(rows.join("\n"), body), 1);
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:
${rows.join("\n")}`,
  );
});

test.describe("file boundary comments", () => {
  test("comments inside end-of-file insertions get opposite slash rows", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
        ctx("prefix", 20),
        ctx("shared_before", [
          "SHARED_BEFORE_EOF_ADDITION",
          "SHARED_AFTER_BODY",
          "SHARED_AFTER_END",
        ]),
        add("eof_added", ["EOF_ADDED_COMMENT_TARGET", "EOF_ADDED_RETURN"]),
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);
    await expect(
      terminal.getByText("EOF_ADDED_COMMENT_TARGET", { strict: false }),
    ).toBeVisible();

    const body = "INLINE_E2E_EOF_ADDITION_BODY";
    await createInlineComment(terminal, body, { side: "right", line: 24 });

    const rows = await waitForBuffer(terminal, (visibleRows) =>
      visibleRows.some((row) => row.includes(body) && row.includes("╱")),
    );
    captureTerminal(terminal, "inline comments - eof addition");

    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
    assert.equal(occurrences(rows.join("\n"), body), 1);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  });

  test("comments inside end-of-file deletions get opposite slash rows", async ({
    terminal,
  }) => {
    const scenario = diffScenario([
      file("src/inline.lua", [
        ctx("prefix", 20),
        ctx("shared_before", [
          "SHARED_BEFORE_EOF_DELETION",
          "SHARED_AFTER_BODY",
          "SHARED_AFTER_END",
        ]),
        del("eof_deleted", [
          "EOF_DELETED_COMMENT_TARGET",
          "EOF_DELETED_RETURN",
        ]),
      ]),
    ]);
    const repo = createRepoFromDiffScenario(scenario);
    await openReviewForRepo(terminal, repo);
    await expect(
      terminal.getByText("EOF_DELETED_COMMENT_TARGET", { strict: false }),
    ).toBeVisible();

    const body = "INLINE_E2E_EOF_DELETION_BODY";
    await createInlineComment(terminal, body, { side: "left", line: 24 });

    const rows = await waitForBuffer(terminal, (visibleRows) =>
      visibleRows.some((row) => row.includes(body) && row.includes("╱")),
    );
    captureTerminal(terminal, "inline comments - eof deletion");

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
  });
});

test("multiple threads and replies at the same target keep the shared tail aligned", async ({
  terminal,
}) => {
  const repo = createAddedBlockInlineCommentRepo();
  await openReviewForRepo(terminal, repo);
  const firstBody = "INLINE_E2E_SAME_TARGET_FIRST";
  const replyBody = "INLINE_E2E_SAME_TARGET_REPLY";
  const secondBody = "INLINE_E2E_SAME_TARGET_SECOND";
  await createInlineComment(terminal, firstBody, { side: "right", line: 202 });
  runLua(
    terminal,
    `require('unified_review.session.manager').reply(nil, ${luaString(replyBody)})`,
  );
  await expect(terminal.getByText(replyBody, { strict: false })).toBeVisible();
  await createInlineComment(terminal, secondBody, { side: "right", line: 202 });

  const marker = "SHARED_AFTER_ADDED_BLOCK";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(firstBody) && row.includes("╱")) &&
      visibleRows.some((row) => row.includes(replyBody) && row.includes("╱")) &&
      visibleRows.some(
        (row) => row.includes(secondBody) && row.includes("╱"),
      ) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(
    terminal,
    "inline comments - same target threads and replies",
  );
  {
    const bodyRow = rows.find((row) => row.includes(firstBody));
    assert.ok(bodyRow, `expected visible body row ${firstBody}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(firstBody) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  }
  {
    const bodyRow = rows.find((row) => row.includes(replyBody));
    assert.ok(bodyRow, `expected visible body row ${replyBody}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(replyBody) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  }
  {
    const bodyRow = rows.find((row) => row.includes(secondBody));
    assert.ok(bodyRow, `expected visible body row ${secondBody}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(secondBody) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  }
  assert.equal(occurrences(rows.join("\n"), firstBody), 1);
  assert.equal(occurrences(rows.join("\n"), replyBody), 1);
  assert.equal(occurrences(rows.join("\n"), secondBody), 1);
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:
${rows.join("\n")}`,
  );
});

test("long multi-paragraph comments that wrap keep the shared tail aligned", async ({
  terminal,
}) => {
  const repo = createSmallAddedBlockRepo();
  await openReviewForRepo(terminal, repo);
  const body =
    "INLINE_E2E_LONG_BODY_START " +
    "wraps across the inline block with enough words to force multiple display rows in the comment renderer " +
    "and it also has a second paragraph.\n\nINLINE_E2E_LONG_BODY_SECOND_PARAGRAPH";
  await createInlineComment(terminal, body, { side: "right", line: 2 });

  const marker = "SHARED_AFTER_SMALL_ADDED";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some(
        (row) =>
          row.includes("INLINE_E2E_LONG_BODY_START") && row.includes("╱"),
      ) &&
      visibleRows.some(
        (row) =>
          row.includes("INLINE_E2E_LONG_BODY_SECOND_PARAGRAPH") &&
          row.includes("╱"),
      ) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(terminal, "inline comments - long wrapped body");
  {
    const bodyToken = "INLINE_E2E_LONG_BODY_START";
    const bodyRow = rows.find((row) => row.includes(bodyToken));
    assert.ok(bodyRow, `expected visible body row ${bodyToken}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(
      bodyRow.indexOf(bodyToken) >= midpoint,
      `got:
${bodyRow}`,
    );
    assert.ok(
      bodyRow.indexOf("╱") < midpoint,
      `got:
${bodyRow}`,
    );
  }
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:
${rows.join("\n")}`,
  );
});

test("comments near adjacent hunks do not disturb later hunk alignment", async ({
  terminal,
}) => {
  const repo = createAdjacentHunksRepo();
  await openReviewForRepo(terminal, repo);
  await expect(
    terminal.getByText("ADJACENT_FIRST_ADDED_TARGET", { strict: false }),
  ).toBeVisible();

  const body = "INLINE_E2E_ADJACENT_HUNKS_BODY";
  await createInlineComment(terminal, body, { side: "right", line: 14 });

  const marker = "SHARED_AFTER_ADJACENT_HUNKS";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(body) && row.includes("╱")) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(terminal, "inline comments - adjacent hunks");
  {
    const bodyRow = rows.find((row) => row.includes(body));
    assert.ok(bodyRow, `expected visible body row ${body}`);
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(bodyRow.indexOf(body) >= midpoint, `got:\n${bodyRow}`);
    assert.ok(bodyRow.indexOf("╱") < midpoint, `got:\n${bodyRow}`);
  }
  assert.equal(occurrences(rows.join("\n"), body), 1);
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected shared marker ${marker} on both sides of one row; got:
${rows.join("\n")}`,
  );
});
