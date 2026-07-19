import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { join } from "node:path";
import { formatLocalReviewForAgent } from "./lib/artifacts.ts";
import { buildReviewExportInit } from "./lib/nvim-scripts.ts";
import {
  commandExists,
  createTempDir,
  fileExists,
  lastInterestingLines,
  readJsonIfExists,
  readTextIfExists,
  removeTempDir,
  runInteractiveNvim,
  type NvimRunResult,
  writeText,
} from "./lib/nvim.ts";

export type NvimDiagnostics = {
  status?: string;
  message?: string;
  path?: string;
  format?: string;
  bytes?: number;
  thread_count?: number;
  exported_thread_count?: number;
  empty?: boolean;
  v_errmsg?: string;
  v_exiting?: number;
  messages?: string;
  modified_buffers?: Array<{ name: string; buftype?: string }>;
};

export type DiffReviewDependencies = {
  commandExists: typeof commandExists;
  createTempDir: typeof createTempDir;
  fileExists: typeof fileExists;
  readJsonIfExists: typeof readJsonIfExists;
  readTextIfExists: typeof readTextIfExists;
  removeTempDir: typeof removeTempDir;
  runInteractiveNvim: typeof runInteractiveNvim;
  writeText: typeof writeText;
};

const defaultDependencies: DiffReviewDependencies = {
  commandExists,
  createTempDir,
  fileExists,
  readJsonIfExists,
  readTextIfExists,
  removeTempDir,
  runInteractiveNvim,
  writeText,
};

export function formatNvimExitDetails(
  result: NvimRunResult,
  diagnostics: NvimDiagnostics | undefined,
  log: string | undefined,
): string {
  const details = [
    result.signal
      ? `nvim was terminated by ${result.signal}`
      : `nvim exited with code ${result.exitCode ?? "unknown"}`,
  ];
  if (diagnostics?.status) details.push(`export status: ${diagnostics.status}`);
  if (diagnostics?.message)
    details.push(`export message: ${diagnostics.message}`);
  if (diagnostics?.thread_count !== undefined) {
    details.push(
      `threads: ${diagnostics.exported_thread_count ?? "?"}/${diagnostics.thread_count} exported`,
    );
  }
  if (diagnostics?.v_errmsg) details.push(`v:errmsg: ${diagnostics.v_errmsg}`);
  if (diagnostics?.modified_buffers?.length) {
    details.push(
      `modified buffers: ${diagnostics.modified_buffers
        .map(
          (buf) =>
            `${buf.name || "[No Name]"}${buf.buftype ? ` (${buf.buftype})` : ""}`,
        )
        .join(", ")}`,
    );
  }
  const messages = lastInterestingLines(diagnostics?.messages);
  if (messages) details.push(`:messages:\n${messages}`);
  const logTail = lastInterestingLines(log, 8);
  if (logTail) details.push(`NVIM_LOG_FILE tail:\n${logTail}`);
  return details.join("\n");
}

export function registerDiffReviewExtension(
  pi: ExtensionAPI,
  dependencies: DiffReviewDependencies = defaultDependencies,
): void {
  pi.registerCommand("review", {
    description:
      "Open Neovim to review a diff, then insert the exported review Markdown into the editor",
    handler: async (_args, ctx) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify("/review requires the interactive TUI", "error");
        return;
      }

      if (!(await dependencies.commandExists(pi, ctx.cwd, "nvim"))) {
        ctx.ui.notify("nvim was not found on PATH.", "error");
        return;
      }

      const tempDir = dependencies.createTempDir("pi-nvim-review-");
      const reviewPath = join(tempDir, "review.md");
      const diagnosticsPath = join(tempDir, "diagnostics.json");
      const nvimLogPath = join(tempDir, "nvim.log");
      const initPath = join(tempDir, "review-init.lua");
      dependencies.writeText(
        initPath,
        buildReviewExportInit(reviewPath, diagnosticsPath),
      );

      let keepTempDir = false;
      const result = await dependencies.runInteractiveNvim(
        ctx,
        [
          "--cmd",
          "let g:auto_session_enabled = v:false",
          "--cmd",
          "lua vim.g.session_autoload = false",
          "-S",
          initPath,
          "-c",
          "UnifiedReview",
        ],
        { NVIM_LOG_FILE: nvimLogPath },
      );

      try {
        if (result.error) {
          ctx.ui.notify(`Failed to launch nvim: ${result.error}`, "error");
          return;
        }

        const diagnostics =
          dependencies.readJsonIfExists<NvimDiagnostics>(diagnosticsPath);
        const review = dependencies.readTextIfExists(reviewPath)?.trim();
        const log = dependencies.readTextIfExists(nvimLogPath);

        if (result.exitCode !== 0 && !review) {
          keepTempDir = true;
          ctx.ui.notify(
            `${formatNvimExitDetails(result, diagnostics, log)}\nDiagnostics retained in ${tempDir}`,
            "warning",
          );
          return;
        }

        if (!dependencies.fileExists(reviewPath)) {
          ctx.ui.notify(
            "Neovim did not export a review. Add comments with <leader>rc before exiting.",
            "warning",
          );
          return;
        }

        if (!review) {
          ctx.ui.notify("Neovim exported an empty review.", "warning");
          return;
        }

        ctx.ui.setEditorText(formatLocalReviewForAgent(review));
        ctx.ui.notify(
          result.exitCode === 0
            ? "Inserted Neovim review into the editor."
            : `Inserted Neovim review despite ${formatNvimExitDetails(result, diagnostics, log).split("\n")[0]}.`,
          result.exitCode === 0 ? "info" : "warning",
        );
      } finally {
        if (!keepTempDir) dependencies.removeTempDir(tempDir);
      }
    },
  });
}

export default function (pi: ExtensionAPI): void {
  registerDiffReviewExtension(pi);
}
