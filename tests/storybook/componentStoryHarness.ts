import { expect, test } from "@microsoft/tui-test";
import type { Terminal } from "@microsoft/tui-test/lib/terminal/term.js";
import { captureTerminal, writeArtifactIndex } from "../tui/artifacts.js";

const nvimBin = process.env.NVIM_BIN || "nvim";

const nvimArgs = [
  "--clean",
  "-n",
  "--cmd",
  "set termguicolors",
  "--cmd",
  "set rtp^=.",
  "--cmd",
  "lua package.path='tests/?.lua;tests/?/init.lua;'..package.path",
  "+lua vim.notify('COMPONENT_STORYBOOK_READY')",
];

export function useComponentStorybookTerminal(
  options: { columns?: number; rows?: number } = {},
) {
  test.use({
    columns: options.columns ?? 100,
    rows: options.rows ?? 28,
    program: {
      file: nvimBin,
      args: nvimArgs,
    },
  });

  test.afterEach(async ({ terminal }) => {
    terminal.write("\u001c\u000e");
    terminal.write(":qa!\r");
  });
}

export async function openComponentStory(terminal: Terminal, story: string) {
  await expect(terminal.getByText("COMPONENT_STORYBOOK_READY")).toBeVisible();
  terminal.write(
    `:lua require('storybook.component_storybook').open('${story}')\r`,
  );
}

export async function expectComponentStory(
  terminal: Terminal,
  story: string,
  title: string,
) {
  await openComponentStory(terminal, story);
  await expect(terminal.getByText(title, { strict: false })).toBeVisible();
}

export function captureComponentStory(terminal: Terminal, name: string) {
  captureTerminal(terminal, `components - ${name}`);
  writeArtifactIndex({
    title: "Components Storybook",
    filename: "components-storybook.html",
    prefix: "components-storybook",
  });
}
