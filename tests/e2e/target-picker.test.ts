import { expect, test } from "@microsoft/tui-test";
import type { Terminal } from "@microsoft/tui-test/lib/terminal/term.js";
import { captureTerminal } from "./artifacts.js";
import { add, del, diffScenario, file } from "./diffDsl.js";
import {
  configureNvimTest,
  createRepoFromDiffScenario,
  delay,
  vimEscapePath,
} from "./helpers.js";

configureNvimTest(test, { columns: 120, rows: 36 });

function createWorkingTreeRepo() {
  return createRepoFromDiffScenario(
    diffScenario([
      file("src/picker.txt", [
        del("old", ["PICKER_BASE_VALUE"]),
        add("target", ["PICKER_WORKING_TARGET"]),
      ]),
    ]),
    "unified-review-picker-e2e-",
    { commitAfter: false },
  );
}

function createCommitRangeRepo() {
  return createRepoFromDiffScenario(
    diffScenario([
      file("src/range.txt", [
        del("old", ["PICKER_RANGE_BASE_VALUE"]),
        add("target", ["PICKER_COMMIT_RANGE_TARGET"]),
      ]),
    ]),
    "unified-review-picker-e2e-",
  );
}

async function cdIntoRepo(terminal: Terminal, repo: string) {
  await expect(terminal.getByText("UNIFIED_REVIEW_E2E_READY")).toBeVisible();
  terminal.write(`:cd ${vimEscapePath(repo)}\r`);
  await delay(50);
}

test("UnifiedReview opens the target picker and selects working-tree changes", async ({
  terminal,
}) => {
  const repo = createWorkingTreeRepo();
  await cdIntoRepo(terminal, repo);

  terminal.write(":UnifiedReview\r");
  await expect(
    terminal.getByText("Unified Review", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("Working tree changes", { strict: false }),
  ).toBeVisible();
  captureTerminal(terminal, "target picker - working tree choices");

  terminal.write("\r");
  await expect(terminal.getByText(/Loaded [0-9]+ changed file/g)).toBeVisible();
  terminal.write("\r");
  await expect(
    terminal.getByText("PICKER_WORKING", { strict: false }),
  ).toBeVisible();
});

test("commit range picker shows inline validation and then opens a valid range", async ({
  terminal,
}) => {
  const repo = createCommitRangeRepo();
  await cdIntoRepo(terminal, repo);

  terminal.write(":UnifiedReview\r");
  await expect(
    terminal.getByText("Unified Review", { strict: false }),
  ).toBeVisible();
  terminal.write("range\r");
  await expect(terminal.getByText("b  base", { strict: false })).toBeVisible();
  captureTerminal(terminal, "target picker - commit range choices");

  terminal.write("b\r");
  await expect(
    terminal.getByText("Base and head must be different", { strict: false }),
  ).toBeVisible();
  captureTerminal(terminal, "target picker - commit range validation");

  terminal.write("jb\r");
  await expect(terminal.getByText(/Loaded [0-9]+ changed file/g)).toBeVisible();
  terminal.write("\r");
  await expect(
    terminal.getByText("PICKER_COMMIT_RANGE", { strict: false }),
  ).toBeVisible();
});
