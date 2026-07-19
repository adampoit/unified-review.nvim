import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { join } from "node:path";
import {
  feedbackSchema,
  formatReviewPrompt,
  isAgentFeedback,
  isContextArtifact,
  isSelectionArtifact,
  type ContextArtifact,
  type SelectionArtifact,
} from "./lib/artifacts.ts";
import {
  buildContextInit,
  buildImportInit,
  buildOpenInit,
} from "./lib/nvim-scripts.ts";
import {
  commandExists,
  createTempDir,
  lastInterestingLines,
  readJsonIfExists,
  removeTempDir,
  runHeadlessNvim,
  runInteractiveNvim,
  type NvimRunResult,
  writeText,
} from "./lib/nvim.ts";

export type NvimDiagnostics = {
  status?: string;
  message?: string;
  v_errmsg?: string;
  messages?: string;
};

export type ImportDiagnostics = NvimDiagnostics & {
  result?: {
    imported_threads?: number;
    imported_comments?: number;
    updated_threads?: number;
    skipped?: unknown[];
    warnings?: unknown[];
    session_id?: string;
  };
};

type ReviewWorkspace = {
  tempDir: string;
  selectionPath: string;
  contextPath: string;
  feedbackPath: string;
  importDiagnosticsPath: string;
  selection: SelectionArtifact;
  context: ContextArtifact;
};

type ImportedReview = ReviewWorkspace & {
  keepTempDir?: boolean;
};

export type AiReviewDependencies = {
  commandExists: typeof commandExists;
  createTempDir: typeof createTempDir;
  readJsonIfExists: typeof readJsonIfExists;
  removeTempDir: typeof removeTempDir;
  runHeadlessNvim: typeof runHeadlessNvim;
  runInteractiveNvim: typeof runInteractiveNvim;
  writeText: typeof writeText;
};

const defaultDependencies: AiReviewDependencies = {
  commandExists,
  createTempDir,
  readJsonIfExists,
  removeTempDir,
  runHeadlessNvim,
  runInteractiveNvim,
  writeText,
};

export function nvimExitSummary(
  result: NvimRunResult,
  diagnostics?: NvimDiagnostics,
): string {
  const details = [
    result.signal
      ? `nvim was terminated by ${result.signal}`
      : `nvim exited with code ${result.exitCode ?? "unknown"}`,
  ];
  if (diagnostics?.status) details.push(`status: ${diagnostics.status}`);
  if (diagnostics?.message) details.push(`message: ${diagnostics.message}`);
  if (diagnostics?.v_errmsg) details.push(`v:errmsg: ${diagnostics.v_errmsg}`);
  const messages = lastInterestingLines(diagnostics?.messages, 10);
  if (messages) details.push(`:messages:\n${messages}`);
  return details.join("\n");
}

export function registerAiReviewExtension(
  pi: ExtensionAPI,
  dependencies: AiReviewDependencies = defaultDependencies,
): void {
  let pendingReview: ReviewWorkspace | undefined;
  let importedReviewToOpen: ImportedReview | undefined;
  let promptingToOpenReview = false;

  const removeReview = (review: ReviewWorkspace | undefined) => {
    if (review) dependencies.removeTempDir(review.tempDir);
  };

  pi.on("session_shutdown", async () => {
    removeReview(pendingReview);
    if (importedReviewToOpen?.tempDir !== pendingReview?.tempDir)
      removeReview(importedReviewToOpen);
    pendingReview = undefined;
    importedReviewToOpen = undefined;
  });

  pi.on("agent_settled", async (_event, ctx) => {
    if (promptingToOpenReview || !importedReviewToOpen || ctx.mode !== "tui")
      return;
    promptingToOpenReview = true;
    const review = importedReviewToOpen;
    importedReviewToOpen = undefined;
    try {
      const openNow = await ctx.ui.confirm(
        "Open Neovim review now?",
        "AI review feedback was imported as local draft comments.",
      );
      if (openNow) {
        const openInitPath = join(review.tempDir, "open-init.lua");
        dependencies.writeText(
          openInitPath,
          buildOpenInit(review.selection.target),
        );
        const result = await dependencies.runInteractiveNvim(ctx, [
          "-S",
          openInitPath,
        ]);
        if (result.error || result.exitCode !== 0) {
          ctx.ui.notify(
            result.error
              ? `Failed to launch nvim: ${result.error}`
              : nvimExitSummary(result),
            "warning",
          );
        }
      }
    } finally {
      promptingToOpenReview = false;
      if (review.keepTempDir) {
        ctx.ui.notify(
          `Import warnings retained in ${review.tempDir}`,
          "warning",
        );
      } else {
        removeReview(review);
      }
    }
  });

  pi.registerTool({
    name: "submit_ai_review_feedback",
    label: "Submit AI Review Feedback",
    description:
      "Submit structured unified-review agent feedback for the active /ai-review workflow.",
    promptSnippet:
      "Submit unified-review.agent-feedback.v1 JSON after completing an /ai-review code review.",
    promptGuidelines: [
      "Use submit_ai_review_feedback exactly once when completing an /ai-review workflow; do not write review JSON to arbitrary files yourself.",
    ],
    parameters: feedbackSchema,
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      if (!isAgentFeedback(params)) {
        throw new Error("AI review feedback does not match the v1 contract.");
      }
      const pending = pendingReview;
      if (!pending) {
        throw new Error(
          "No active /ai-review workflow is waiting for feedback.",
        );
      }

      const review = {
        ...params,
        author: params.author ?? "pi-agent",
        source: {
          name: params.source?.name ?? "pi-coding-agent",
          run_id: params.source?.run_id ?? pending.selection.selected_at,
          model:
            params.source?.model ??
            (ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined),
        },
      };
      dependencies.writeText(
        pending.feedbackPath,
        JSON.stringify(review, null, 2),
      );

      const importInitPath = join(pending.tempDir, "import-init.lua");
      dependencies.writeText(
        importInitPath,
        buildImportInit(
          pending.feedbackPath,
          pending.importDiagnosticsPath,
          pending.selection.target,
        ),
      );
      const nvimResult = await dependencies.runHeadlessNvim(
        pi,
        ctx.cwd,
        importInitPath,
      );
      const diagnostics = dependencies.readJsonIfExists<ImportDiagnostics>(
        pending.importDiagnosticsPath,
      );
      if (
        nvimResult.exitCode !== 0 ||
        !diagnostics ||
        diagnostics.status === "error"
      ) {
        throw new Error(
          `Failed to import review feedback.\n${nvimExitSummary(nvimResult, diagnostics)}`,
        );
      }

      const imported = diagnostics.result?.imported_comments ?? 0;
      const updated = diagnostics.result?.updated_threads ?? 0;
      const skipped = diagnostics.result?.skipped?.length ?? 0;
      ctx.ui.notify(
        `Imported ${imported} AI review comment(s), updated ${updated}, skipped ${skipped}.`,
        skipped > 0 ? "warning" : "info",
      );

      const keepTempDir = Boolean(diagnostics.result?.warnings?.length);
      if (pendingReview === pending) pendingReview = undefined;
      if (ctx.mode === "tui") {
        importedReviewToOpen = { ...pending, keepTempDir };
      } else if (!keepTempDir) {
        removeReview(pending);
      }

      return {
        content: [
          {
            type: "text" as const,
            text: `Imported ${imported} AI review comment(s), updated ${updated}, skipped ${skipped}.`,
          },
        ],
        details: { diagnostics },
        terminate: true,
      };
    },
  });

  pi.registerCommand("ai-review", {
    description:
      "Pick a unified-review target in Neovim, ask the agent to review it, and import feedback as draft comments",
    handler: async (_args, ctx) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify("/ai-review requires the interactive TUI", "error");
        return;
      }
      if (pendingReview || importedReviewToOpen || promptingToOpenReview) {
        ctx.ui.notify("An /ai-review workflow is already active.", "warning");
        return;
      }
      if (!(await dependencies.commandExists(pi, ctx.cwd, "nvim"))) {
        ctx.ui.notify("nvim was not found on PATH.", "error");
        return;
      }

      const tempDir = dependencies.createTempDir("pi-ai-review-");
      const selectionPath = join(tempDir, "selection.json");
      const contextPath = join(tempDir, "context.json");
      const contextDiagnosticsPath = join(tempDir, "context-diagnostics.json");
      const feedbackPath = join(tempDir, "feedback.json");
      const importDiagnosticsPath = join(tempDir, "import-diagnostics.json");
      let keepTempDir = false;

      try {
        const selectResult = await dependencies.runInteractiveNvim(ctx, [
          "--cmd",
          "let g:auto_session_enabled = v:false",
          "--cmd",
          "lua vim.g.session_autoload = false",
          "-c",
          `UnifiedReview agent-select ${selectionPath}`,
        ]);
        if (selectResult.error) {
          ctx.ui.notify(
            `Failed to launch nvim: ${selectResult.error}`,
            "error",
          );
          return;
        }

        const selectionValue = dependencies.readJsonIfExists(selectionPath);
        if (!isSelectionArtifact(selectionValue)) {
          if (selectResult.exitCode !== 0) {
            keepTempDir = true;
            ctx.ui.notify(
              `${nvimExitSummary(selectResult)}\nDiagnostics retained in ${tempDir}`,
              "warning",
            );
          } else {
            ctx.ui.notify("No review target was selected.", "warning");
          }
          return;
        }

        const contextInitPath = join(tempDir, "context-init.lua");
        dependencies.writeText(
          contextInitPath,
          buildContextInit(
            contextPath,
            selectionValue.target,
            contextDiagnosticsPath,
          ),
        );
        const contextResult = await dependencies.runHeadlessNvim(
          pi,
          ctx.cwd,
          contextInitPath,
        );
        const contextDiagnostics =
          dependencies.readJsonIfExists<NvimDiagnostics>(
            contextDiagnosticsPath,
          );
        if (
          contextResult.exitCode !== 0 ||
          contextDiagnostics?.status === "error"
        ) {
          keepTempDir = true;
          ctx.ui.notify(
            `Failed to export AI review context.\n${nvimExitSummary(contextResult, contextDiagnostics)}\nTemp files retained in ${tempDir}.`,
            "error",
          );
          return;
        }

        const contextValue = dependencies.readJsonIfExists(contextPath);
        if (!isContextArtifact(contextValue)) {
          keepTempDir = true;
          ctx.ui.notify(
            `Neovim wrote an invalid review context. Temp files retained in ${tempDir}.`,
            "error",
          );
          return;
        }

        pendingReview = {
          tempDir,
          selectionPath,
          contextPath,
          feedbackPath,
          importDiagnosticsPath,
          selection: selectionValue,
          context: contextValue,
        };
        keepTempDir = true;
        ctx.ui.notify(
          `Selected ${selectionValue.label ?? "review target"}; queued AI review for ${contextValue.files?.length ?? 0} file(s).`,
          "info",
        );
        pi.sendUserMessage(formatReviewPrompt(contextValue), {
          deliverAs: "followUp",
        });
      } finally {
        if (!keepTempDir) dependencies.removeTempDir(tempDir);
      }
    },
  });
}

export default function (pi: ExtensionAPI): void {
  registerAiReviewExtension(pi);
}
