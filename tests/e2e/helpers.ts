import { expect } from "@microsoft/tui-test";
import type { Terminal } from "@microsoft/tui-test/lib/terminal/term.js";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { DiffScenario } from "./diffDsl.js";
import { scenarioFiles } from "./diffDsl.js";

const nvimBin = process.env.NVIM_BIN || "nvim";

export const delay = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));

export const nvimArgs = [
  "--clean",
  "-n",
  "-u",
  "tests/minimal_init.lua",
  "--cmd",
  "set rtp^=.",
  "+lua require('unified_review').setup({}); vim.notify('UNIFIED_REVIEW_E2E_READY')",
];

export const nvimProgram = {
  file: nvimBin,
  args: nvimArgs,
};

export function configureNvimTest(
  test: typeof import("@microsoft/tui-test").test,
  options: { columns?: number; rows?: number } = {},
) {
  test.use({
    columns: options.columns || 120,
    rows: options.rows || 36,
    program: nvimProgram,
  });

  test.afterEach(async ({ terminal }) => {
    terminal.write("\u001c\u000e");
    terminal.write(":qa!\r");
  });
}

export function vimEscapePath(path: string) {
  return path.replace(/\\/g, "\\\\").replace(/ /g, "\\ ");
}

export function luaString(value: string) {
  return JSON.stringify(value);
}

export function writeRepoFiles(
  root: string,
  files: Record<string, string[] | null>,
) {
  for (const [path, lines] of Object.entries(files)) {
    const fullPath = join(root, path);
    if (lines === null) {
      rmSync(fullPath, { force: true });
      continue;
    }
    mkdirSync(join(fullPath, ".."), { recursive: true });
    writeFileSync(fullPath, lines.join("\n") + "\n");
  }
}

export function createRepoWithFiles(
  beforeFiles: Record<string, string[] | null>,
  afterFiles: Record<string, string[] | null>,
  prefix = "unified-review-e2e-",
  opts: { commitAfter?: boolean } = {},
) {
  const root = mkdtempSync(join(tmpdir(), prefix));
  const git = (...args: string[]) => execFileSync("git", ["-C", root, ...args]);

  git("init", "--initial-branch", "master");
  git("config", "user.email", "e2e@example.invalid");
  git("config", "user.name", "E2E");
  writeRepoFiles(root, beforeFiles);
  git("add", "-A");
  git("commit", "--allow-empty", "-m", "base");

  writeRepoFiles(root, afterFiles);
  if (opts.commitAfter !== false) {
    git("add", "-A");
    git("commit", "-m", "change");
  }

  return root;
}

export function createRepoFromDiffScenario(
  scenario: DiffScenario,
  prefix = "unified-review-e2e-",
  opts: { commitAfter?: boolean } = {},
) {
  const { beforeFiles, afterFiles } = scenarioFiles(scenario);
  return createRepoWithFiles(beforeFiles, afterFiles, prefix, opts);
}

export function terminalRows(terminal: Terminal) {
  return terminal.getViewableBuffer().map((row) => row.join(""));
}

export function occurrences(text: string, needle: string) {
  return text.split(needle).length - 1;
}

export async function waitForBuffer(
  terminal: Terminal,
  predicate: (rows: string[]) => boolean,
) {
  for (let attempt = 0; attempt < 40; attempt++) {
    const rows = terminalRows(terminal);
    if (predicate(rows)) {
      return rows;
    }
    await delay(100);
  }
  return terminalRows(terminal);
}

export function runLua(terminal: Terminal, lua: string) {
  terminal.write(`:lua ${lua}\r`);
}

export async function openReviewForRepo(terminal: Terminal, repo: string) {
  await expect(terminal.getByText("UNIFIED_REVIEW_E2E_READY")).toBeVisible();
  terminal.write(`:cd ${vimEscapePath(repo)}\r`);
  terminal.write(":UnifiedReview local HEAD~1..HEAD\r");
  await expect(terminal.getByText(/Loaded [0-9]+ changed file/g)).toBeVisible();
  terminal.write("\r");
}

export async function reopenReviewForRepo(terminal: Terminal, repo: string) {
  terminal.write(":UnifiedReview close\r");
  await delay(150);
  terminal.write(`:cd ${vimEscapePath(repo)}\r`);
  terminal.write(":UnifiedReview local HEAD~1..HEAD\r");
  await expect(terminal.getByText(/Loaded [0-9]+ changed file/g)).toBeVisible();
  terminal.write("\r");
}
