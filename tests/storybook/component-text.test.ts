import { expect, test } from "@microsoft/tui-test";
import {
  captureComponentStory,
  expectComponentStory,
  useComponentStorybookTerminal,
} from "./componentStoryHarness.js";

useComponentStorybookTerminal();

test("storybook: text, line, text_line, and blank components", async ({
  terminal,
}) => {
  await expectComponentStory(terminal, "text", "Text components");
  await expect(terminal.getByText("Text", { strict: false })).toBeVisible();
  await expect(
    terminal.getByText("text_line renders", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("Inline spans", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("blank() intentionally", { strict: false }),
  ).toBeVisible();
  captureComponentStory(terminal, "storybook text");
});
