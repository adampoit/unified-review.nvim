import { expect, test } from "@microsoft/tui-test";
import {
  captureComponentStory,
  expectComponentStory,
  useComponentStorybookTerminal,
} from "./componentStoryHarness.js";

useComponentStorybookTerminal();

test("storybook: section, divider, sep, and blank structure", async ({
  terminal,
}) => {
  await expectComponentStory(terminal, "structure", "Structural components");
  await expect(terminal.getByText("Section heading")).toBeVisible();
  await expect(
    terminal.getByText("Rows can be mixed", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("Separators", { strict: false }),
  ).toBeVisible();
  await expect(
    terminal.getByText("blank row above", { strict: false }),
  ).toBeVisible();
  captureComponentStory(terminal, "storybook structure");
});
