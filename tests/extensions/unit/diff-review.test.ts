import assert from "node:assert/strict";
import test from "node:test";
import {
  registerDiffReviewExtension,
  type DiffReviewDependencies,
} from "../../../extensions/diff-review.ts";

function harness(options: { mode?: string; review?: string } = {}) {
  let command: any;
  const notifications: Array<[string, string]> = [];
  const editorText: string[] = [];
  const writes = new Map<string, string>();
  const removed: string[] = [];
  let commandChecks = 0;

  const pi = {
    registerCommand(_name: string, definition: any) {
      command = definition;
    },
  } as any;
  const dependencies: DiffReviewDependencies = {
    async commandExists() {
      commandChecks++;
      return true;
    },
    createTempDir: () => "/tmp/diff-review-test",
    fileExists: (path) =>
      path.endsWith("review.md") && options.review !== undefined,
    readJsonIfExists: (() => ({
      status: "saved",
      thread_count: 1,
      exported_thread_count: 1,
    })) as DiffReviewDependencies["readJsonIfExists"],
    readTextIfExists: (path) =>
      path.endsWith("review.md") ? options.review : undefined,
    removeTempDir: (path) => removed.push(path),
    runInteractiveNvim: async () => ({ exitCode: 0, stderr: "" }),
    writeText: (path, content) => writes.set(path, content),
  };
  const ctx = {
    mode: options.mode ?? "tui",
    cwd: "/repo",
    ui: {
      notify: (message: string, level: string) =>
        notifications.push([message, level]),
      setEditorText: (text: string) => editorText.push(text),
    },
  };

  registerDiffReviewExtension(pi, dependencies);
  return {
    command,
    ctx,
    notifications,
    editorText,
    writes,
    removed,
    get commandChecks() {
      return commandChecks;
    },
  };
}

test("/review rejects RPC mode before attempting a terminal handoff", async () => {
  const instance = harness({ mode: "rpc" });
  await instance.command.handler("", instance.ctx);
  assert.equal(instance.commandChecks, 0);
  assert.deepEqual(instance.notifications, [
    ["/review requires the interactive TUI", "error"],
  ]);
});

test("/review inserts exported feedback and cleans its workspace", async () => {
  const instance = harness({ review: "# Code Review\n\n- `a.ts:2`: Fix it." });
  await instance.command.handler("", instance.ctx);

  assert.equal(instance.editorText.length, 1);
  assert.match(instance.editorText[0], /a\.ts:2/);
  assert.match(
    instance.writes.get("/tmp/diff-review-test/review-init.lua") ?? "",
    /summary\.save_active/,
  );
  assert.deepEqual(instance.removed, ["/tmp/diff-review-test"]);
  assert.deepEqual(instance.notifications.at(-1), [
    "Inserted Neovim review into the editor.",
    "info",
  ]);
});

test("/review reports a missing export without changing the editor", async () => {
  const instance = harness();
  await instance.command.handler("", instance.ctx);
  assert.deepEqual(instance.editorText, []);
  assert.match(instance.notifications.at(-1)?.[0] ?? "", /did not export/);
  assert.deepEqual(instance.removed, ["/tmp/diff-review-test"]);
});
