import { defineConfig } from "@microsoft/tui-test";

export default defineConfig({
  testMatch: "tests/{e2e,storybook}/**/*.test.ts",
  retries: 1,
  trace: true,
});
