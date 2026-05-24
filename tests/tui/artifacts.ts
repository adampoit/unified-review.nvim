import { existsSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";

type TerminalCell = {
  getChars(): string;
  getFgColor(): number;
  getBgColor(): number;
  isFgDefault?(): boolean;
  isFgPalette?(): boolean;
  isFgRGB?(): boolean;
  isBgDefault?(): boolean;
  isBgPalette?(): boolean;
  isBgRGB?(): boolean;
  isBold?(): boolean;
  isDim?(): boolean;
  isItalic?(): boolean;
  isUnderline?(): boolean;
  isStrikethrough?(): boolean;
  isInverse?(): boolean;
};

type TerminalLine = {
  getCell(x: number, cell?: TerminalCell): TerminalCell | undefined;
};

type TerminalBuffer = {
  baseY: number;
  length: number;
  getLine(y: number): TerminalLine | undefined;
};

type ArtifactTerminal = {
  _term?: {
    cols: number;
    rows: number;
    buffer?: { active?: TerminalBuffer };
  };
  serialize(): { view: string };
};

const enabled = process.env.UNIFIED_REVIEW_E2E_ARTIFACTS === "1";
const root = process.env.UNIFIED_REVIEW_E2E_ARTIFACT_DIR || "tui-artifacts";
let counter = 0;

const ANSI_16 = [
  "#000000",
  "#cd0000",
  "#00cd00",
  "#cdcd00",
  "#0000ee",
  "#cd00cd",
  "#00cdcd",
  "#e5e5e5",
  "#7f7f7f",
  "#ff0000",
  "#00ff00",
  "#ffff00",
  "#5c5cff",
  "#ff00ff",
  "#00ffff",
  "#ffffff",
];

function ansi256(index: number) {
  if (index < 0) return undefined;
  if (index < ANSI_16.length) return ANSI_16[index];
  if (index >= 16 && index <= 231) {
    const value = index - 16;
    const r = Math.floor(value / 36);
    const g = Math.floor((value % 36) / 6);
    const b = value % 6;
    const channel = (n: number) => (n === 0 ? 0 : 55 + n * 40);
    return rgb(channel(r), channel(g), channel(b));
  }
  if (index >= 232 && index <= 255) {
    const gray = 8 + (index - 232) * 10;
    return rgb(gray, gray, gray);
  }
  return undefined;
}

function rgb(r: number, g: number, b: number) {
  const hex = (n: number) => n.toString(16).padStart(2, "0");
  return `#${hex(r)}${hex(g)}${hex(b)}`;
}

function packedRgb(value: number) {
  if (value == null || value < 0) return undefined;
  return `#${value.toString(16).padStart(6, "0").slice(-6)}`;
}

function cellColor(cell: TerminalCell | undefined, kind: "fg" | "bg") {
  if (!cell) return undefined;
  if (kind === "fg") {
    if (cell.isFgDefault?.()) return undefined;
    if (cell.isFgPalette?.()) return ansi256(cell.getFgColor());
    if (cell.isFgRGB?.()) return packedRgb(cell.getFgColor());
  } else {
    if (cell.isBgDefault?.()) return undefined;
    if (cell.isBgPalette?.()) return ansi256(cell.getBgColor());
    if (cell.isBgRGB?.()) return packedRgb(cell.getBgColor());
  }
  return undefined;
}

function slug(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "")
    .slice(0, 96);
}

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function styleForCell(cell: TerminalCell | undefined) {
  const styles: string[] = [];
  const fg = cellColor(cell, "fg");
  const bg = cellColor(cell, "bg");
  if (fg) styles.push(`color:${fg}`);
  if (bg) styles.push(`background-color:${bg}`);
  if (cell?.isBold?.()) styles.push("font-weight:700");
  if (cell?.isDim?.()) styles.push("opacity:0.65");
  if (cell?.isItalic?.()) styles.push("font-style:italic");
  if (cell?.isUnderline?.()) styles.push("text-decoration:underline");
  if (cell?.isStrikethrough?.()) styles.push("text-decoration:line-through");
  if (cell?.isInverse?.()) styles.push("filter:invert(1)");
  return styles.join(";");
}

function terminalHtml(terminal: ArtifactTerminal) {
  const term = terminal._term;
  const buffer = term?.buffer?.active;
  if (!term || !buffer) {
    return escapeHtml(terminal.serialize().view);
  }

  const rows: string[] = [];
  for (let y = buffer.baseY; y < buffer.length; y++) {
    const termLine = buffer.getLine(y);
    const cells: string[] = [];
    let reusableCell: TerminalCell | undefined;
    for (let x = 0; x < term.cols; x++) {
      reusableCell = termLine?.getCell(x, reusableCell);
      const raw = reusableCell?.getChars() ?? "";
      const chars = raw === "" ? " " : raw;
      const style = styleForCell(reusableCell);
      cells.push(
        style
          ? `<span style="${style}">${escapeHtml(chars)}</span>`
          : escapeHtml(chars),
      );
    }
    rows.push(cells.join(""));
  }
  return rows.join("\n");
}

function terminalFrameHtml(terminal: ArtifactTerminal, name: string) {
  return `<style>
  :root { color-scheme: dark; }
  body { margin: 0; padding: 24px; background: #111; color: #ddd; }
  h1 { font: 16px/1.4 ui-sans-serif, system-ui, sans-serif; margin: 0 0 16px; color: #f2f2f2; }
  pre {
    display: inline-block;
    margin: 0;
    padding: 16px;
    border: 1px solid #3a3a3a;
    border-radius: 12px;
    background: #0b0b0b;
    box-shadow: 0 16px 48px rgba(0, 0, 0, 0.35);
    font: 13px/1.2 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    white-space: pre;
  }
</style>
<h1>${escapeHtml(name)}</h1>
<pre>${terminalHtml(terminal)}</pre>`;
}

function terminalSvg(terminal: ArtifactTerminal, name: string) {
  const term = terminal._term;
  const cols = term?.cols ?? 100;
  const rows = term?.rows ?? terminal.serialize().view.split("\n").length;
  const width = cols * 8 + 80;
  const height = rows * 16 + 128;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <rect width="100%" height="100%" fill="#111"/>
  <foreignObject x="0" y="0" width="${width}" height="${height}">
    <div xmlns="http://www.w3.org/1999/xhtml">${terminalFrameHtml(terminal, name)}</div>
  </foreignObject>
</svg>
`;
}

function artifactTitle(file: string) {
  return basename(file, ".html")
    .replace(/^\d+-/, "")
    .replace(/-/g, " ")
    .replace(/\b\w/g, (match) => match.toUpperCase());
}

export function writeArtifactIndex(
  options: { title?: string; filename?: string; prefix?: string } = {},
) {
  if (!enabled) {
    return;
  }

  mkdirSync(root, { recursive: true });
  const title = options.title || "TUI Artifacts";
  const filename = options.filename || "index.html";
  const prefix = options.prefix;
  const files = readdirSync(root)
    .filter((file) => file.endsWith(".html"))
    .filter((file) => file !== filename)
    .filter((file) => !file.endsWith("-index.html"))
    .filter((file) => {
      const normalized = file.replace(/^\d+-/, "");
      if (prefix) return normalized.startsWith(prefix);
      return !normalized.startsWith("components-storybook-");
    })
    .sort();

  const links = files
    .map((file) => {
      const stem = basename(file, ".html");
      const svg = `${stem}.svg`;
      const txt = `${stem}.txt`;
      const formats = [];
      if (existsSync(join(root, svg)))
        formats.push(`<a href="${escapeHtml(svg)}">svg</a>`);
      if (existsSync(join(root, txt)))
        formats.push(`<a href="${escapeHtml(txt)}">txt</a>`);
      return `<li>
        <a href="${escapeHtml(file)}">${escapeHtml(artifactTitle(file))}</a>
        <small>${formats.join(" · ")}</small>
      </li>`;
    })
    .join("\n");

  writeFileSync(
    join(root, filename),
    `<!doctype html>
<meta charset="utf-8">
<title>${escapeHtml(title)}</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; padding: 32px; background: #111; color: #ddd; font: 15px/1.5 ui-sans-serif, system-ui, sans-serif; }
  h1 { margin: 0 0 20px; color: #f2f2f2; }
  ul { display: grid; gap: 10px; margin: 0; padding: 0; list-style: none; max-width: 840px; }
  li { display: flex; justify-content: space-between; gap: 20px; padding: 12px 14px; border: 1px solid #333; border-radius: 10px; background: #181818; }
  a { color: #89b4fa; text-decoration: none; }
  a:hover { text-decoration: underline; }
  small { color: #999; white-space: nowrap; }
</style>
<h1>${escapeHtml(title)}</h1>
<ul>
${links}
</ul>
`,
  );
}

export function captureTerminal(terminal: unknown, name: string) {
  if (!enabled) {
    return;
  }

  const artifactTerminal = terminal as ArtifactTerminal;
  mkdirSync(root, { recursive: true });
  const id = `${String(++counter).padStart(2, "0")}-${slug(name)}`;
  const snapshot = artifactTerminal.serialize();
  const textPath = join(root, `${id}.txt`);
  const htmlPath = join(root, `${id}.html`);
  const svgPath = join(root, `${id}.svg`);
  writeFileSync(textPath, snapshot.view);
  writeFileSync(
    htmlPath,
    `<!doctype html>
<meta charset="utf-8">
<title>${escapeHtml(name)}</title>
${terminalFrameHtml(artifactTerminal, name)}
`,
  );
  writeFileSync(svgPath, terminalSvg(artifactTerminal, name));
  writeArtifactIndex({ title: "TUI Artifacts" });
}
