import { expect, test } from "@microsoft/tui-test";
import type { Terminal } from "@microsoft/tui-test/lib/terminal/term.js";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { captureTerminal } from "../artifacts.js";
import { add, ctx, del, diffScenario, file } from "../diffDsl.js";
import {
  configureNvimTest,
  createRepoFromDiffScenario,
  occurrences,
} from "../helpers.js";
import {
  createInlineComment,
  createStartOfFileAdditionRepo,
  luaString,
  openReviewForRepo,
  runLua,
  waitForBuffer,
} from "./helpers.js";

type DiffLineTarget = {
  side: "left" | "right";
  needle: string;
};

type DiffLineVisualRow = DiffLineTarget & {
  bufferRow: number;
  visualRow: number;
  line: string;
};

async function collectDiffLineVisualRows(
  terminal: Terminal,
  targets: DiffLineTarget[],
): Promise<DiffLineVisualRow[]> {
  const outputPath = join(
    mkdtempSync(join(tmpdir(), "unified-review-visual-rows-")),
    "rows.json",
  );
  const marker = `UR_VISUAL_ROWS_${Date.now()}`;
  const script = `
local output_path = ${luaString(outputPath)}
local targets = vim.json.decode(${luaString(JSON.stringify(targets))})
local session = require('unified_review.session.manager').active()
assert(session and session.ui, 'no active review session')
local namespaces = vim.api.nvim_get_namespaces()
local ns_inline = namespaces.unified_review_inline_virt
local ok_highlights, highlights = pcall(require, 'codediff.ui.highlights')
local ns_filler = ok_highlights and highlights.ns_filler or nil
local ns_highlight = ok_highlights and highlights.ns_highlight or nil
local function collect_marks(buf)
  local marks = {}
  for _, ns in ipairs({ ns_filler, ns_highlight, ns_inline }) do
    if ns then
      for _, raw in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        local details = raw[4] or {}
        if details.virt_lines then
          table.insert(marks, {
            row = raw[2],
            above = details.virt_lines_above == true,
            count = #details.virt_lines,
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
  for _, mark in ipairs(collect_marks(buf)) do
    if mark.row < row or (mark.row == row and mark.above) then
      visual = visual + mark.count
    end
  end
  return visual
end
local function find_row(buf, needle)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(needle, 1, true) then
      return index - 1, line
    end
  end
  error('line not found: ' .. needle)
end
local function buf_for(side)
  return side == 'left' and session.ui.left_buffer or session.ui.right_buffer
end
local rows = {}
for _, target in ipairs(targets) do
  local buf = buf_for(target.side)
  local row, line = find_row(buf, target.needle)
  table.insert(rows, {
    side = target.side,
    needle = target.needle,
    bufferRow = row + 1,
    visualRow = visual_before(buf, row) + 1,
    line = line,
  })
end
vim.fn.writefile({ vim.json.encode(rows) }, output_path)
`;
  runLua(
    terminal,
    `local f=loadstring(${luaString(script)}); local ok,err=pcall(f); vim.g.ur_e2e_visual_rows_result = ok and ${luaString(`${marker}_OK`)} or (${luaString(`${marker}_ERR: `)}..tostring(err))`,
  );
  terminal.write(":echo g:ur_e2e_visual_rows_result\r");
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(`${marker}_OK`)) ||
      visibleRows.some((row) => row.includes(`${marker}_ERR`)),
  );
  assert.ok(
    rows.some((row) => row.includes(`${marker}_OK`)),
    `failed to collect visual rows from Neovim; got:\n${rows.join("\n")}`,
  );
  return JSON.parse(readFileSync(outputPath, "utf8"));
}

configureNvimTest(test, { columns: 180, rows: 40 });

test("right-side comments in later insertions do not move earlier replacement alignment", async ({
  terminal,
}) => {
  const scenario = diffScenario([
    file("src/comment-alignment-regression.txt", [
      ctx("prefix", [
        "CTX_PREFIX_001",
        "CTX_PREFIX_002",
        "CTX_PREFIX_003",
        "CTX_PREFIX_004",
      ]),
      del("old_block", [
        "OLD_WRAPPER_START",
        "SHARED_SETTING_ALPHA",
        "SHARED_SETTING_BETA",
        "SUBSTITUTERS_START",
        "OLD_SUBSTITUTER_001",
        "OLD_SUBSTITUTER_002",
        "SUBSTITUTERS_CLOSE",
        "KEYS_START",
        "OLD_KEY_001",
        "OLD_KEY_002",
        "TRUSTED_CLOSE",
        "OLD_WRAPPER_CLOSE",
      ]),
      add("new_block", [
        "NEW_OUTER_START",
        "NEW_INNER_START",
        "SHARED_SETTING_ALPHA",
        "SHARED_SETTING_BETA",
        "SUBSTITUTERS_START",
        "NEW_SUBSTITUTER_001",
        "SUBSTITUTERS_CLOSE",
        "KEYS_START",
        "NEW_KEY_001",
        "TRUSTED_CLOSE",
        "NEW_INNER_CLOSE",
        "",
        "NEW_EXTRA_OPTIONS_START",
        "NEW_COMMENT_TARGET",
        "NEW_EXTRA_OPTIONS_CLOSE",
        "NEW_OUTER_CLOSE",
        "",
        "NEW_SCRIPT_001",
        "NEW_SCRIPT_002",
        "NEW_SCRIPT_003",
        "NEW_SCRIPT_004",
        "NEW_SCRIPT_005",
        "",
      ]),
      ctx("shared_tail", ["SHARED_TAIL_001", "SHARED_TAIL_002"]),
    ]),
  ]);
  const repo = createRepoFromDiffScenario(scenario);
  await openReviewForRepo(terminal, repo);

  const rightAlignedLine = scenario.labels["new_block:10"].text;
  await expect(
    terminal.getByText(rightAlignedLine, { strict: false }),
  ).toBeVisible();

  const body = "INLINE_E2E_INSERTION_COMMENT_BODY";
  await createInlineComment(terminal, body, {
    side: "right",
    line: scenario.labels["new_block:14"].newLine || 0,
    path: scenario.path,
  });
  captureTerminal(terminal, "inline comments - insertion regression");

  const [leftLine, rightLine] = await collectDiffLineVisualRows(terminal, [
    { side: "left", needle: scenario.labels["old_block:11"].text },
    { side: "right", needle: rightAlignedLine },
  ]);
  assert.equal(
    leftLine.visualRow,
    rightLine.visualRow,
    `expected ${leftLine.line} and ${rightLine.line} to share a visual row:\n${JSON.stringify(
      { leftLine, rightLine },
      null,
      2,
    )}`,
  );
});

test.describe("narrow terminal inline comment layout", () => {
  test.use({ columns: 100, rows: 24 });

  test("wrapped comments preserve spacer rows in narrow panes", async ({
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

    const body =
      "NARROWBODY wraps enough text to exercise the narrower side by side panes";
    await createInlineComment(terminal, body, { side: "right", line: 2 });

    const marker = "SHARED_AFTER";
    const rows = await waitForBuffer(
      terminal,
      (visibleRows) =>
        visibleRows.some(
          (row) => row.includes("NARROWBODY") && row.includes("╱"),
        ) && visibleRows.some((row) => occurrences(row, marker) >= 2),
    );
    captureTerminal(terminal, "inline comments - narrow layout");

    const bodyRow = rows.find((row) => row.includes("NARROWBODY"));
    assert.ok(
      bodyRow,
      `expected visible wrapped body row in:\n${rows.join("\n")}`,
    );
    const midpoint = Math.floor(bodyRow.length / 2);
    assert.ok(
      bodyRow.indexOf("NARROWBODY") >= midpoint,
      `expected NARROWBODY on the right side; got:\n${bodyRow}`,
    );
    assert.ok(
      bodyRow.indexOf("╱") < midpoint,
      `expected a left-side slash spacer in narrow layout; got:\n${bodyRow}`,
    );
    assert.ok(
      rows.some((row) => occurrences(row, marker) >= 2),
      `expected ${marker} on both sides of one row; got:\n${rows.join("\n")}`,
    );
  });
});

// Neovim does not reliably display virt_lines_above before the top line in this TUI setup;
// keep the scenario documented until we have a renderer strategy for true file-start insertions.
test.skip("comments at the start of a file-level insertion keep the shared tail aligned", async ({
  terminal,
}) => {
  const repo = createStartOfFileAdditionRepo();
  await openReviewForRepo(terminal, repo);
  await expect(
    terminal.getByText("ADDED_AT_FILE_START", { strict: false }),
  ).toBeVisible();

  const body = "INLINE_E2E_START_OF_FILE_ADDITION_BODY";
  await createInlineComment(terminal, body, { side: "right", line: 1 });

  const marker = "SHARED_AFTER_START_ADDITION";
  const rows = await waitForBuffer(
    terminal,
    (visibleRows) =>
      visibleRows.some((row) => row.includes(body)) &&
      visibleRows.some((row) => occurrences(row, marker) >= 2),
  );
  captureTerminal(terminal, "inline comments - start of file addition");

  assert.ok(
    rows.some((row) => row.includes(body)),
    `expected ${body} in:\n${rows.join("\n")}`,
  );
  assert.ok(
    rows.some((row) => occurrences(row, marker) >= 2),
    `expected ${marker} on both sides of one row; got:\n${rows.join("\n")}`,
  );
});
