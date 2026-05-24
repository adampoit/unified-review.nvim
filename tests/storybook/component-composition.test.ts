import { expect, test } from "@microsoft/tui-test";
import {
  captureComponentStory,
  expectComponentStory,
  useComponentStorybookTerminal,
} from "./componentStoryHarness.js";

useComponentStorybookTerminal();

test("storybook: composed review row", async ({ terminal }) => {
  await expectComponentStory(terminal, "composition", "Composed review row");
  await expect(terminal.getByText("selected", { strict: false })).toBeVisible();
  await expect(
    terminal.getByText("src/app.lua", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("Reusable rows", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("toggle state", { strict: false }),
  ).toBeVisible();
  captureComponentStory(terminal, "storybook composition");
});
