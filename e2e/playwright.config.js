const { defineConfig } = require("@playwright/test");

const baseURL = process.env.PLAYWRIGHT_BASE_URL || "http://127.0.0.1:4010";
const shouldStartServer = !process.env.PLAYWRIGHT_BASE_URL;

module.exports = defineConfig({
  testDir: "./tests",
  workers: 1,
  fullyParallel: false,
  timeout: 90_000,
  expect: {
    timeout: 15_000,
  },
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL,
    trace: "retain-on-failure",
    video: "retain-on-failure",
    screenshot: "only-on-failure",
    headless: true,
  },
  webServer: shouldStartServer
    ? {
        command: "PORT=4010 MIX_ENV=dev mix phx.server",
        cwd: "..",
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 180_000,
      }
    : undefined,
});
