import { expect, test } from "@microsoft/tui-test";
import type { Terminal } from "@microsoft/tui-test/lib/terminal/term.js";
import { captureTerminal } from "./artifacts.js";
import { add, ctx, del, diffScenario, file } from "./diffDsl.js";
import {
  configureNvimTest,
  createRepoFromDiffScenario,
  delay,
  vimEscapePath,
} from "./helpers.js";

configureNvimTest(test, { columns: 120, rows: 36 });

function createReviewGitRepo() {
  return createRepoFromDiffScenario(
    diffScenario([
      file("src/app.txt", [
        del("app_old", ["THREAD_BASE_ONE"]),
        add("app_new_one", ["THREAD_TARGET_ONE"]),
        ctx("app_context", ["THREAD_BASE_TWO"]),
        add("app_new_three", ["THREAD_TARGET_THREE"]),
      ]),
      file("src/other.txt", [
        del("other_old", ["OTHER_BASE_ALPHA"]),
        add("other_new", ["OTHER_TARGET"]),
      ]),
    ]),
  );
}

async function openRealReview(terminal: Terminal) {
  const repo = createReviewGitRepo();
  await expect(terminal.getByText("UNIFIED_REVIEW_E2E_READY")).toBeVisible();
  terminal.write(`:cd ${vimEscapePath(repo)}\r`);
  terminal.write(":UnifiedReview local HEAD~1..HEAD\r");
  await expect(terminal.getByText(/Loaded [0-9]+ changed file/g)).toBeVisible();
  terminal.write("\r");
  await expect(
    terminal.getByText("THREAD_TARGET_THREE", { strict: false }),
  ).toBeVisible();
  await delay(500);
  return repo;
}

async function createCommentAtCurrentLine(terminal: Terminal, body: string) {
  terminal.write("\u001c\u000e");
  terminal.write(":UnifiedReview comment\r");
  await expect(terminal.getByText("[:w/<C-s>] save")).toBeVisible();
  await delay(50);
  terminal.write(body);
  await expect(terminal.getByText(body)).toBeVisible();
  terminal.write("\u001c\u000e");
  terminal.write(":write\r");
  await expect(
    terminal.getByText(/Created draft comment/g, { strict: false }),
  ).toBeVisible();
}

test("UnifiedReview local opens a git diff and thread panel empty state", async ({
  terminal,
}) => {
  await openRealReview(terminal);

  await expect(
    terminal.getByText("src/app.txt", { strict: false }),
  ).toBeVisible();
  terminal.write(":UnifiedReview threads\r");
  await expect(
    terminal.getByText("Review Overview", { strict: false }),
  ).toBeVisible();
  await expect(terminal.getByText("No review threads")).toBeVisible();
  captureTerminal(terminal, "thread panel - empty state");
  terminal.write("q");
});

test("comment editor can be driven by keys and comments appear in threads and summary", async ({
  terminal,
}) => {
  await openRealReview(terminal);

  await createCommentAtCurrentLine(terminal, "new top-level e2e comment");

  terminal.write(":UnifiedReview threads\r");
  await expect(
    terminal.getByText("Review Overview", { strict: false }),
  ).toBeVisible();
  await expect(terminal.getByText("new top-", { strict: false })).toBeVisible();
  captureTerminal(terminal, "thread panel - draft comment visible");
  terminal.write("q");

  terminal.write(":UnifiedReview summary\r");
  await expect(terminal.getByText("Review Summary")).toBeVisible();
  await expect(
    terminal.getByText("new top-level e2e comment", { strict: false }),
  ).toBeVisible();
});

test("thread panel supports inline replies without opening another modal", async ({
  terminal,
}) => {
  await openRealReview(terminal);
  await createCommentAtCurrentLine(terminal, "thread root for inline reply");

  terminal.write(":UnifiedReview threads\r");
  await expect(
    terminal.getByText("thread root", { strict: false }),
  ).toBeVisible();

  terminal.write("R");
  await expect(terminal.getByText("Reply")).toBeVisible();
  await expect(
    terminal.getByText("Edit below in this panel", { strict: false }),
  ).toBeVisible();

  terminal.write("inline e2e reply");
  await expect(
    terminal.getByText("inline e2e reply", { strict: false }),
  ).toBeVisible();

  terminal.write("\u001c\u000e");
  terminal.write(
    ":lua vim.api.nvim_feedkeys(vim.keycode('<C-s>'), 'x', false)\r",
  );
  await expect(terminal.getByText("Created draft reply")).toBeVisible();
  captureTerminal(terminal, "thread panel - inline reply saved");
  terminal.write("q");

  terminal.write(":UnifiedReview summary\r");
  await expect(terminal.getByText("Review Summary")).toBeVisible();
  terminal.write("/inline e2e reply\r");
  await expect(
    terminal.getByText("inline e2e reply", { strict: false }),
  ).toBeVisible();
});

test("thread panel supports resolve, reopen, delete, filtering, and jump", async ({
  terminal,
}) => {
  await openRealReview(terminal);
  await createCommentAtCurrentLine(terminal, "rename this from real workflow");

  terminal.write(":UnifiedReview threads\r");
  await expect(terminal.getByText("rename t", { strict: false })).toBeVisible();

  terminal.write("r");
  await expect(
    terminal.getByText("✓ resolved", { strict: false }),
  ).toBeVisible();
  captureTerminal(terminal, "thread panel - resolved draft");
  terminal.write("r");
  await expect(terminal.getByText("✎ draft", { strict: false })).toBeVisible();

  terminal.write("F");
  await expect(terminal.getByText("Filter review threads:")).toBeVisible();
  terminal.write("rename\r");
  await expect(terminal.getByText("rename t", { strict: false })).toBeVisible();
  terminal.write("F");
  await expect(terminal.getByText("Filter review threads:")).toBeVisible();
  terminal.keyBackspace(6);
  terminal.write("\r");
  await expect(terminal.getByText("rename t", { strict: false })).toBeVisible();

  terminal.write("D");
  await expect(
    terminal.getByText("rename t", { strict: false }),
  ).not.toBeVisible();
});

test("summary copy and save are driven through the real summary UI", async ({
  terminal,
}) => {
  await openRealReview(terminal);
  await createCommentAtCurrentLine(terminal, "summary save e2e body");

  terminal.write(":UnifiedReview summary\r");
  await expect(terminal.getByText("Review Summary")).toBeVisible();
  terminal.write("y");
  await expect(terminal.getByText(/Copied [0-9]+ character/g)).toBeVisible();

  const path = `/tmp/unified-review-summary-${Date.now()}.md`;
  terminal.write("w");
  await expect(terminal.getByText("Save review to:")).toBeVisible();
  terminal.keyBackspace(80);
  terminal.write(`${path}\r`);
  await expect(terminal.getByText("Saved review to")).toBeVisible();
  terminal.write(`:edit ${path}\r`);
  await expect(
    terminal.getByText("summary save e2e body", { strict: false }),
  ).toBeVisible();
});

test("help, status, close, and no-session are usable", async ({ terminal }) => {
  await openRealReview(terminal);
  await createCommentAtCurrentLine(terminal, "status visible body");

  terminal.write(":UnifiedReview help\r");
  await expect(terminal.getByText("unified-review help")).toBeVisible();
  await expect(
    terminal.getByText(":UnifiedReview local [base] [head]"),
  ).toBeVisible();
  terminal.write("q");

  terminal.write(":UnifiedReview status\r");
  await expect(
    terminal.getByText(/threads|open/g, { strict: false }),
  ).toBeVisible();

  terminal.write(":UnifiedReview threads\r");
  await expect(
    terminal.getByText("Review Overview", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("Scope: project", { strict: false }),
  ).toBeVisible();
  terminal.write("F");
  await expect(terminal.getByText("Filter review threads:")).toBeVisible();
  terminal.write("status\r");
  await expect(terminal.getByText("status v", { strict: false })).toBeVisible();
  captureTerminal(terminal, "thread panel - filtered status query");
  terminal.write("q");

  terminal.write(":lua require('unified_review.ui.thread_panel').close()\r");
  terminal.write(":UnifiedReview close\r");
  await expect(terminal.getByText("Closed review session")).toBeVisible();
  terminal.write(":UnifiedReview threads\r");
  await expect(terminal.getByText("No active review session")).toBeVisible();
});

test.describe("small terminal layouts", () => {
  test.use({ columns: 80, rows: 24 });

  test("thread panel keeps critical labels visible at 80x24", async ({
    terminal,
  }) => {
    await openRealReview(terminal);

    terminal.write(":UnifiedReview threads\r");
    await expect(
      terminal.getByText("Review Overview", { strict: false }),
    ).toBeVisible();
    await expect(terminal.getByText("Status:")).toBeVisible();
    await expect(terminal.getByText("o/v/d/s/a  states")).toBeVisible();
    captureTerminal(terminal, "thread panel - small terminal");

    terminal.write("F");
    await expect(terminal.getByText("Filter review threads:")).toBeVisible();
    await expect(terminal.getByText("o/v/d/s/a  states")).toBeVisible();
  });
});

test.describe("very small terminal layout", () => {
  test.use({ columns: 70, rows: 20 });

  test("thread panel still exposes a closeable usable surface", async ({
    terminal,
  }) => {
    await openRealReview(terminal);

    terminal.write(":UnifiedReview threads\r");
    await expect(
      terminal.getByText("Review Overview", { strict: false }),
    ).toBeVisible();
    await expect(terminal.getByText("Status:")).toBeVisible();
    terminal.write(":lua require('unified_review.ui.thread_panel').close()\r");
    await expect(
      terminal.getByText("Review Overview", { strict: false }),
    ).not.toBeVisible();
  });
});
