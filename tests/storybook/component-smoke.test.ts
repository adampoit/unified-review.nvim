import { expect, test } from "@microsoft/tui-test";
import {
  captureComponentStory,
  expectComponentStory,
  useComponentStorybookTerminal,
} from "./componentStoryHarness.js";

useComponentStorybookTerminal();

test("storybook: component document smoke test", async ({ terminal }) => {
  await expectComponentStory(terminal, "smoke", "Component smoke");
  await expect(terminal.getByText("CR  open", { strict: false })).toBeVisible();
  await expect(
    terminal.getByText("ok  ready", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("Context row", { strict: false }),
  ).toBeVisible();
  captureComponentStory(terminal, "storybook smoke");
});
