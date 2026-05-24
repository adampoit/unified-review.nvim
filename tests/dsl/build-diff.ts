#!/usr/bin/env node
import { diffScenario, type FileSpec } from "../e2e/diffDsl.ts";

function readStdin(): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      data += chunk;
    });
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", reject);
  });
}

function normalizeInput(input: unknown): FileSpec[] {
  if (Array.isArray(input)) {
    return input as FileSpec[];
  }
  if (
    input &&
    typeof input === "object" &&
    Array.isArray((input as { files?: unknown }).files)
  ) {
    return (input as { files: FileSpec[] }).files;
  }
  throw new Error("expected a file spec array or an object with a files array");
}

try {
  const input = JSON.parse(await readStdin());
  process.stdout.write(
    `${JSON.stringify(diffScenario(normalizeInput(input)))}\n`,
  );
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
}
