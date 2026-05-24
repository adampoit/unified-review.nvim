import { expect, test } from "@microsoft/tui-test";
import {
  captureComponentStory,
  expectComponentStory,
  useComponentStorybookTerminal,
} from "./componentStoryHarness.js";

useComponentStorybookTerminal();

test("storybook: badge and separator components", async ({ terminal }) => {
  await expectComponentStory(terminal, "badges", "Badge components");
  await expect(
    terminal.getByText("j/k  move", { strict: false }),
  ).toBeVisible();
  await expect(terminal.getByText("CR  open", { strict: false })).toBeVisible();
  await expect(
    terminal.getByText("draft  local", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("stale  needs", { strict: false }),
  ).toBeVisible();
  captureComponentStory(terminal, "storybook badges separators");
});
