import { expect, test } from "@microsoft/tui-test";
import {
  captureComponentStory,
  expectComponentStory,
  useComponentStorybookTerminal,
} from "./componentStoryHarness.js";

useComponentStorybookTerminal();

test("storybook: space, pad_left, pad_right, and truncate components", async ({
  terminal,
}) => {
  await expectComponentStory(
    terminal,
    "padding",
    "Padding and truncation components",
  );
  await expect(terminal.getByText("pad_left", { strict: false })).toBeVisible();
  await expect(
    terminal.getByText("pad_right", { strict: false }),
  ).toBeVisible();
  await expect(terminal.getByText("truncate", { strict: false })).toBeVisible();
  await expect(terminal.getByText("emoji 😀", { strict: false })).toBeVisible();
  captureComponentStory(terminal, "storybook padding truncation");
});
