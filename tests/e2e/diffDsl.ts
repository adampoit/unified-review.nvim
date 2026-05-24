export type OpKind = "context" | "added" | "deleted";

export type Operation = {
  kind: OpKind;
  label: string;
  count?: number;
  lines?: string[];
};

export type HunkSpec = {
  ops: Operation[];
  gapBefore?: number;
};

export type FileSpec = {
  path: string;
  hunks: HunkSpec[];
};

type BuiltFile = {
  path: string;
  beforeLines: string[];
  afterLines: string[];
  patch: string;
  additions: number;
  deletions: number;
};

type Label = {
  path: string;
  kind: OpKind;
  text: string;
  side: "both" | "left" | "right";
  oldLine?: number;
  newLine?: number;
};

export type DiffScenario = {
  path: string;
  patch: string;
  files: BuiltFile[];
  labels: Record<string, Label>;
  additions: number;
  deletions: number;
};

const prefixByKind: Record<OpKind, string> = {
  context: "CTX",
  added: "ADD",
  deleted: "DEL",
};

function sanitizeToken(value: string): string {
  const token = value
    .trim()
    .replace(/[^A-Za-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .toUpperCase();
  return token || "LINE";
}

function generatedText(kind: OpKind, label: string, index: number): string {
  return `${prefixByKind[kind]}_${sanitizeToken(label)}_${String(index).padStart(3, "0")}`;
}

function op(kind: OpKind, label: string, countOrLines: number | string[] = 1) {
  if (Array.isArray(countOrLines)) {
    return { kind, label, lines: countOrLines };
  }
  return { kind, label, count: countOrLines };
}

export function ctx(label: string, countOrLines: number | string[] = 1) {
  return op("context", label, countOrLines);
}

export function add(label: string, countOrLines: number | string[] = 1) {
  return op("added", label, countOrLines);
}

export function del(label: string, countOrLines: number | string[] = 1) {
  return op("deleted", label, countOrLines);
}

export function hunk(ops: Operation[], opts: { gapBefore?: number } = {}) {
  return { ops, gapBefore: opts.gapBefore || 0 };
}

export function file(path: string, opsOrHunks: Array<Operation | HunkSpec>) {
  const hasHunks = opsOrHunks.some((entry) => "ops" in entry);
  return {
    path,
    hunks: hasHunks
      ? (opsOrHunks as HunkSpec[])
      : [hunk(opsOrHunks as Operation[])],
  };
}

function opLines(operation: Operation): string[] {
  if (operation.lines) {
    return operation.lines;
  }
  const count = operation.count || 1;
  return Array.from({ length: count }, (_, index) =>
    generatedText(operation.kind, operation.label, index + 1),
  );
}

function addGapLines(
  beforeLines: string[],
  afterLines: string[],
  count: number,
) {
  const base = beforeLines.length;
  for (let index = 0; index < count; index += 1) {
    const text = generatedText("context", "gap", base + index + 1);
    beforeLines.push(text);
    afterLines.push(text);
  }
}

function hunkLineCounts(ops: Operation[]) {
  let oldCount = 0;
  let newCount = 0;
  for (const operation of ops) {
    const lines = opLines(operation);
    if (operation.kind === "context" || operation.kind === "deleted") {
      oldCount += lines.length;
    }
    if (operation.kind === "context" || operation.kind === "added") {
      newCount += lines.length;
    }
  }
  return { oldCount, newCount };
}

function recordLabel(
  labels: DiffScenario["labels"],
  filePath: string,
  operation: Operation,
  index: number,
  text: string,
  oldLine: number | undefined,
  newLine: number | undefined,
) {
  labels[`${operation.label}:${index}`] = {
    path: filePath,
    kind: operation.kind,
    text,
    side:
      operation.kind === "deleted"
        ? "left"
        : operation.kind === "added"
          ? "right"
          : "both",
    oldLine,
    newLine,
  };
}

function buildFile(spec: FileSpec, labels: DiffScenario["labels"]): BuiltFile {
  const beforeLines: string[] = [];
  const afterLines: string[] = [];
  const patchLines = [
    `diff --git a/${spec.path} b/${spec.path}`,
    `--- a/${spec.path}`,
    `+++ b/${spec.path}`,
  ];
  let additions = 0;
  let deletions = 0;

  for (const currentHunk of spec.hunks) {
    addGapLines(beforeLines, afterLines, currentHunk.gapBefore || 0);
    let oldLine = beforeLines.length + 1;
    let newLine = afterLines.length + 1;
    const { oldCount, newCount } = hunkLineCounts(currentHunk.ops);
    patchLines.push(`@@ -${oldLine},${oldCount} +${newLine},${newCount} @@`);

    for (const operation of currentHunk.ops) {
      const lines = opLines(operation);
      lines.forEach((text, index) => {
        const labelIndex = index + 1;
        if (operation.kind === "context") {
          beforeLines.push(text);
          afterLines.push(text);
          patchLines.push(` ${text}`);
          recordLabel(
            labels,
            spec.path,
            operation,
            labelIndex,
            text,
            oldLine,
            newLine,
          );
          oldLine += 1;
          newLine += 1;
        } else if (operation.kind === "deleted") {
          beforeLines.push(text);
          patchLines.push(`-${text}`);
          recordLabel(
            labels,
            spec.path,
            operation,
            labelIndex,
            text,
            oldLine,
            undefined,
          );
          oldLine += 1;
          deletions += 1;
        } else {
          afterLines.push(text);
          patchLines.push(`+${text}`);
          recordLabel(
            labels,
            spec.path,
            operation,
            labelIndex,
            text,
            undefined,
            newLine,
          );
          newLine += 1;
          additions += 1;
        }
      });
    }
  }

  return {
    path: spec.path,
    beforeLines,
    afterLines,
    patch: `${patchLines.join("\n")}\n`,
    additions,
    deletions,
  };
}

export function diffScenario(files: FileSpec[]): DiffScenario {
  const labels: DiffScenario["labels"] = {};
  const builtFiles = files.map((spec) => buildFile(spec, labels));
  const additions = builtFiles.reduce(
    (sum, builtFile) => sum + builtFile.additions,
    0,
  );
  const deletions = builtFiles.reduce(
    (sum, builtFile) => sum + builtFile.deletions,
    0,
  );

  return {
    path: builtFiles[0]?.path || "",
    patch:
      builtFiles
        .map((builtFile) => builtFile.patch.replace(/\n$/, ""))
        .join("\n") + "\n",
    files: builtFiles,
    labels,
    additions,
    deletions,
  };
}

export function scenarioFiles(scenario: DiffScenario) {
  const beforeFiles: Record<string, string[]> = {};
  const afterFiles: Record<string, string[]> = {};
  for (const builtFile of scenario.files) {
    beforeFiles[builtFile.path] = builtFile.beforeLines;
    afterFiles[builtFile.path] = builtFile.afterLines;
  }
  return { beforeFiles, afterFiles };
}
