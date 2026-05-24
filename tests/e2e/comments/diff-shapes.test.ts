import { expect, test } from "@microsoft/tui-test";
import {
  add,
  ctx,
  del,
  diffScenario,
  file,
  hunk,
  scenarioFiles,
} from "../diffDsl.js";
import { configureNvimTest, createRepoWithFiles } from "../helpers.js";
import {
  luaString,
  openReviewForRepo,
  runLua,
  waitForBuffer,
} from "./helpers.js";

configureNvimTest(test, { columns: 160, rows: 36 });

const cases = [
  {
    name: "addition-between-context",
    scenario: diffScenario([
      file("src/addition-between-context.txt", [
        ctx("before", 2),
        add("target", 2),
        ctx("after", 2),
      ]),
    ]),
    anchorLabel: "target:1",
  },
  {
    name: "deletion-between-context",
    scenario: diffScenario([
      file("src/deletion-between-context.txt", [
        ctx("before", 2),
        del("target", 2),
        ctx("after", 2),
      ]),
    ]),
    anchorLabel: "target:1",
  },
  {
    name: "equal-replacement",
    scenario: diffScenario([
      file("src/equal-replacement.txt", [
        ctx("before", 2),
        del("old", 2),
        add("new", 2),
        ctx("after", 2),
      ]),
    ]),
    anchorLabel: "new:1",
  },
  {
    name: "right-longer-replacement",
    scenario: diffScenario([
      file("src/right-longer-replacement.txt", [
        ctx("before", 2),
        del("old", 1),
        add("new", 3),
        ctx("after", 2),
      ]),
    ]),
    anchorLabel: "new:2",
  },
  {
    name: "left-longer-replacement",
    scenario: diffScenario([
      file("src/left-longer-replacement.txt", [
        ctx("before", 2),
        del("old", 3),
        add("new", 1),
        ctx("after", 2),
      ]),
    ]),
    anchorLabel: "old:2",
  },
  {
    name: "adjacent-delete-add-blocks",
    scenario: diffScenario([
      file("src/adjacent-delete-add-blocks.txt", [
        ctx("before", 1),
        del("old_block", 2),
        add("new_block", 2),
        ctx("after", 1),
      ]),
    ]),
    anchorLabel: "new_block:1",
  },
  {
    name: "moved-line-shape",
    scenario: diffScenario([
      file("src/moved-line-shape.txt", [
        ctx("before", 1),
        del("move_from", ["MOV_MOVED_PAYLOAD_001"]),
        ctx("middle", 8),
        add("move_to", ["MOV_MOVED_PAYLOAD_001"]),
        ctx("after", 1),
      ]),
    ]),
    anchorLabel: "move_to:1",
  },
  {
    name: "start-of-file-addition",
    scenario: diffScenario([
      file("src/start-of-file-addition.txt", [
        add("target", 2),
        ctx("after", 3),
      ]),
    ]),
    anchorLabel: "target:1",
  },
  {
    name: "end-of-file-addition",
    scenario: diffScenario([
      file("src/end-of-file-addition.txt", [
        ctx("before", 3),
        add("target", 2),
      ]),
    ]),
    anchorLabel: "target:1",
  },
  {
    name: "end-of-file-deletion",
    scenario: diffScenario([
      file("src/end-of-file-deletion.txt", [
        ctx("before", 3),
        del("target", 2),
      ]),
    ]),
    anchorLabel: "target:1",
  },
  {
    name: "multi-hunk-change",
    scenario: diffScenario([
      file("src/multi-hunk-change.txt", [
        hunk([
          ctx("first_before", 2),
          del("first_old", 1),
          add("first_new", 1),
          ctx("first_after", 2),
        ]),
        hunk(
          [
            ctx("second_before", 2),
            add("second_new", 2),
            ctx("second_after", 2),
          ],
          { gapBefore: 8 },
        ),
      ]),
    ]),
    anchorLabel: "second_new:1",
  },
  {
    name: "two-file-change",
    scenario: diffScenario([
      file("src/two-file-inline.txt", [
        ctx("inline_before", 2),
        add("inline_target", 1),
        ctx("inline_after", 2),
      ]),
      file("src/two-file-other.txt", [
        ctx("other_before", 1),
        del("other_old", 1),
        add("other_new", 1),
        ctx("other_after", 1),
      ]),
    ]),
    anchorLabel: "inline_target:1",
  },
];

test("renders deterministic diff-shape scenarios", async ({ terminal }) => {
  const beforeFiles = {};
  const afterFiles = {};

  for (const { scenario } of cases) {
    const files = scenarioFiles(scenario);
    Object.assign(beforeFiles, files.beforeFiles);
    Object.assign(afterFiles, files.afterFiles);
  }

  const repo = createRepoWithFiles(
    beforeFiles,
    afterFiles,
    "unified-review-diff-shapes-e2e-",
  );
  await openReviewForRepo(terminal, repo);

  for (const { name, scenario, anchorLabel } of cases) {
    const marker = `UR_SELECTED_${name}`;
    runLua(
      terminal,
      `local s=require('unified_review.session.manager').active(); for i,f in ipairs(s.files or {}) do if f.path == ${luaString(scenario.path)} or f.old_path == ${luaString(scenario.path)} then require('unified_review.session.selection').select_file(s, i); require('unified_review.ui.diff_view').render(s); vim.g.ur_e2e_selected_diff_scenario = ${luaString(marker)}; break end end`,
    );
    terminal.write(":echo g:ur_e2e_selected_diff_scenario\r");
    await waitForBuffer(terminal, (rows) =>
      rows.some((row) => row.includes(marker)),
    );

    await expect(
      terminal.getByText(scenario.labels[anchorLabel].text, { strict: false }),
    ).toBeVisible();
  }
});
