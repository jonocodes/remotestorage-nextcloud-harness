import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: ".",
  outputDir: "/tmp/playwright-output",
  timeout: 120_000,
  expect: { timeout: 10_000 },
  workers: 1,
  reporter: [["list"]],
  use: {
    browserName: "chromium",
    headless: true,
    ignoreHTTPSErrors: true
  }
});
