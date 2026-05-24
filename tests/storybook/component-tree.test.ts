import { expect, test } from "@microsoft/tui-test";
import {
  captureComponentStory,
  expectComponentStory,
  useComponentStorybookTerminal,
} from "./componentStoryHarness.js";

useComponentStorybookTerminal();

test("storybook: tree component supports visible nesting and selected rows", async ({
  terminal,
}) => {
  await expectComponentStory(terminal, "tree", "Tree component");

  await expect(
    terminal.getByText("▾ src/app.lua", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("› ● selected thread: fix nil guard", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("open thread: rename variable", { strict: false }),
  ).toBeVisible();

  const view = terminal
    .getViewableBuffer()
    .map((row) => row.join(""))
    .join("\n");
  expect(view).toContain("  ▾ src/app.lua");
  expect(view).toContain("  › ● selected thread: fix nil guard");

  await expect(
    terminal.getByText("▸ docs/readme.md", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("hidden docs child", { strict: false }),
  ).not.toBeVisible();

  await expect(
    terminal.getByText("selected thread: fix nil guard", { strict: false }),
  ).toHaveBgColor([49, 50, 68]);

  captureComponentStory(terminal, "storybook tree");
});
