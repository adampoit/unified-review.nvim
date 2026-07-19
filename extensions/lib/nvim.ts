import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export type ExecResult = Awaited<ReturnType<ExtensionAPI["exec"]>>;

export type NvimRunResult = {
  exitCode: number | null;
  stderr: string;
  error?: string;
  signal?: NodeJS.Signals | null;
};

export type InteractiveNvimContext = {
  cwd: string;
  ui: {
    custom: <T>(factory: (...args: any[]) => any, options?: any) => Promise<T>;
  };
};

export async function tryExec(
  pi: ExtensionAPI,
  cwd: string,
  command: string,
  args: string[],
  timeout = 5000,
): Promise<ExecResult | undefined> {
  try {
    return await pi.exec(command, args, { cwd, timeout });
  } catch {
    return undefined;
  }
}

export async function commandExists(
  pi: ExtensionAPI,
  cwd: string,
  command: string,
): Promise<boolean> {
  const result = await tryExec(
    pi,
    cwd,
    "bash",
    ["-c", 'command -v "$1"', "--", command],
    2000,
  );
  return result?.code === 0;
}

export function createTempDir(prefix: string): string {
  return mkdtempSync(join(tmpdir(), prefix));
}

export function writeText(path: string, content: string): void {
  writeFileSync(path, content);
}

export function fileExists(path: string): boolean {
  return existsSync(path);
}

export function readTextIfExists(path: string): string | undefined {
  if (!fileExists(path)) return undefined;
  return readFileSync(path, "utf8");
}

export function readJsonIfExists<T>(path: string): T | undefined {
  const text = readTextIfExists(path);
  if (!text) return undefined;
  try {
    return JSON.parse(text) as T;
  } catch {
    return undefined;
  }
}

export function removeTempDir(path: string): void {
  rmSync(path, { recursive: true, force: true });
}

export function luaString(value: string): string {
  return JSON.stringify(value);
}

export function luaJson(value: unknown): string {
  return `vim.json.decode(${luaString(JSON.stringify(value))})`;
}

export function lastInterestingLines(
  text: string | undefined,
  count = 12,
): string {
  return (text ?? "")
    .split("\n")
    .map((line) => line.trimEnd())
    .filter(Boolean)
    .slice(-count)
    .join("\n");
}

export function runInteractiveNvim(
  ctx: InteractiveNvimContext,
  args: string[],
  env?: NodeJS.ProcessEnv,
): Promise<NvimRunResult> {
  return ctx.ui.custom<NvimRunResult>(
    (
      tui: any,
      _theme: any,
      _keybindings: any,
      done: (result: NvimRunResult) => void,
    ) => {
      tui.stop();
      process.stdout.write("\x1b[2J\x1b[H");
      const child = spawnSync("nvim", args, {
        cwd: ctx.cwd,
        stdio: "inherit",
        encoding: "utf8",
        env: { ...process.env, ...env },
      });
      tui.start();
      tui.requestRender(true);
      done({
        exitCode: child.status,
        stderr: "",
        error: child.error?.message,
        signal: child.signal,
      });
      return { render: () => [], invalidate: () => {} };
    },
    { overlay: false },
  );
}

export async function runHeadlessNvim(
  pi: ExtensionAPI,
  cwd: string,
  initPath: string,
  timeout = 120_000,
): Promise<NvimRunResult> {
  const result = await tryExec(
    pi,
    cwd,
    "nvim",
    [
      "--headless",
      "--cmd",
      "let g:auto_session_enabled = v:false",
      "--cmd",
      "lua vim.g.session_autoload = false",
      "-S",
      initPath,
    ],
    timeout,
  );
  return {
    exitCode: result?.code ?? null,
    stderr: result?.stderr ?? "",
  };
}
