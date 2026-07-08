import assert from "node:assert/strict";
import test from "node:test";
import {
  registerAiReviewExtension,
  type AiReviewDependencies,
} from "../../../extensions/ai-review.ts";

function harness() {
  let command: any;
  let tool: any;
  const handlers = new Map<string, (...args: any[]) => any>();
  const notifications: Array<[string, string]> = [];
  const messages: Array<{ content: string; options: unknown }> = [];
  const writes = new Map<string, string>();
  const removed: string[] = [];
  const confirms: boolean[] = [];
  let interactiveRuns = 0;

  const selection = {
    schema: "unified-review.agent-selection.v1",
    selected_at: "2026-01-01T00:00:00Z",
    label: "Current change",
    target: { kind: "local_git", base: "HEAD~1", head: "HEAD" },
  };
  const context = {
    schema: "unified-review.agent-context.v1",
    files: [{ path: "a.ts", raw_patch: "@@ -1 +1 @@" }],
  };
  const diagnostics = {
    status: "imported",
    result: {
      imported_comments: 1,
      updated_threads: 0,
      skipped: [],
      warnings: [],
    },
  };

  const pi = {
    on(name: string, handler: (...args: any[]) => any) {
      handlers.set(name, handler);
    },
    registerCommand(_name: string, definition: any) {
      command = definition;
    },
    registerTool(definition: any) {
      tool = definition;
    },
    sendUserMessage(content: string, options: unknown) {
      messages.push({ content, options });
    },
  } as any;

  const dependencies: AiReviewDependencies = {
    commandExists: async () => true,
    createTempDir: () => "/tmp/ai-review-test",
    readJsonIfExists: ((path: string) => {
      if (path.endsWith("selection.json")) return selection;
      if (path.endsWith("context.json")) return context;
      if (path.endsWith("import-diagnostics.json")) return diagnostics;
      return undefined;
    }) as AiReviewDependencies["readJsonIfExists"],
    removeTempDir: (path) => removed.push(path),
    runHeadlessNvim: async () => ({ exitCode: 0, stderr: "" }),
    runInteractiveNvim: async () => {
      interactiveRuns++;
      return { exitCode: 0, stderr: "" };
    },
    writeText: (path, content) => writes.set(path, content),
  };

  const ctx = {
    mode: "tui",
    cwd: "/repo",
    model: { provider: "test", id: "reviewer" },
    ui: {
      notify: (message: string, level: string) =>
        notifications.push([message, level]),
      confirm: async () => confirms.shift() ?? false,
    },
  };

  registerAiReviewExtension(pi, dependencies);
  return {
    command,
    tool,
    handlers,
    ctx,
    notifications,
    messages,
    writes,
    removed,
    confirms,
    get interactiveRuns() {
      return interactiveRuns;
    },
  };
}

test("/ai-review exports context, queues review, imports feedback, and settles", async () => {
  const instance = harness();
  await instance.command.handler("", instance.ctx);

  assert.equal(instance.messages.length, 1);
  assert.match(instance.messages[0].content, /"path": "a\.ts"/);
  assert.deepEqual(instance.messages[0].options, { deliverAs: "followUp" });
  assert.match(
    instance.writes.get("/tmp/ai-review-test/context-init.lua") ?? "",
    /write_context/,
  );

  const result = await instance.tool.execute(
    "tool-call",
    {
      schema: "unified-review.agent-feedback.v1",
      comments: [
        {
          id: "issue-1",
          body: "Fix this.",
          target: { kind: "file", path: "a.ts" },
        },
      ],
    },
    undefined,
    undefined,
    instance.ctx,
  );
  assert.equal(result.terminate, true);
  assert.match(
    instance.writes.get("/tmp/ai-review-test/feedback.json") ?? "",
    /test\/reviewer/,
  );
  assert.match(
    instance.writes.get("/tmp/ai-review-test/import-init.lua") ?? "",
    /import_file/,
  );
  assert.deepEqual(instance.removed, []);

  await instance.handlers.get("agent_settled")?.({}, instance.ctx);
  assert.deepEqual(instance.removed, ["/tmp/ai-review-test"]);
  assert.equal(instance.interactiveRuns, 1);
});

test("feedback submission fails by throwing when no review is active", async () => {
  const instance = harness();
  await assert.rejects(
    instance.tool.execute(
      "tool-call",
      { schema: "unified-review.agent-feedback.v1", comments: [] },
      undefined,
      undefined,
      instance.ctx,
    ),
    /No active \/ai-review workflow/,
  );
});

test("session shutdown cleans a pending review workspace", async () => {
  const instance = harness();
  await instance.command.handler("", instance.ctx);
  await instance.handlers.get("session_shutdown")?.({}, instance.ctx);
  assert.deepEqual(instance.removed, ["/tmp/ai-review-test"]);
});

test("/ai-review requires true TUI mode", async () => {
  const instance = harness();
  instance.ctx.mode = "rpc";
  await instance.command.handler("", instance.ctx);
  assert.deepEqual(instance.messages, []);
  assert.deepEqual(instance.notifications, [
    ["/ai-review requires the interactive TUI", "error"],
  ]);
});
