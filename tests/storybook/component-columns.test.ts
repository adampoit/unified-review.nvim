import { expect, test } from "@microsoft/tui-test";
import {
  captureComponentStory,
  expectComponentStory,
  useComponentStorybookTerminal,
} from "./componentStoryHarness.js";

useComponentStorybookTerminal();

test("storybook: columns component", async ({ terminal }) => {
  await expectComponentStory(terminal, "columns", "Column component");
  await expect(terminal.getByText("State", { strict: false })).toBeVisible();
  await expect(terminal.getByText("Count", { strict: false })).toBeVisible();
  await expect(
    terminal.getByText("Fixed columns", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("Short text pads", { strict: false }),
  ).toBeVisible();
  captureComponentStory(terminal, "storybook columns");
});
