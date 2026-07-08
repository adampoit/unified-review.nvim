import { expect, test } from "@microsoft/tui-test";
import { resolve } from "node:path";
import { delay } from "./helpers.js";

const piCli = resolve(
  "node_modules/@earendil-works/pi-coding-agent/dist/cli.js",
);

test.use({
  columns: 120,
  rows: 36,
  env: {
    PATH: process.env.PATH,
    VIMINIT: `lua vim.opt.runtimepath:prepend(${JSON.stringify(resolve("."))}); require("unified_review").setup({})`,
  },
  program: {
    file: process.execPath,
    args: [
      piCli,
      "--offline",
      "--approve",
      "--no-extensions",
      "--no-skills",
      "--no-prompt-templates",
      "--no-context-files",
      "-e",
      ".",
    ],
  },
});

test.afterEach(async ({ terminal }) => {
  terminal.write("\u0003");
  await delay(100);
  terminal.write("\u0003");
});

test("pi /review hands the terminal to Neovim and returns cleanly", async ({
  terminal,
}) => {
  await expect(terminal.getByText(/pi v[0-9]/g)).toBeVisible();
  terminal.write("/review\r");

  await expect(terminal.getByText("Unified Review")).toBeVisible();
  terminal.write("\u001b");
  terminal.write(":qa!\r");

  await expect(
    terminal.getByText(/Neovim did not export a review/g),
  ).toBeVisible();
});
