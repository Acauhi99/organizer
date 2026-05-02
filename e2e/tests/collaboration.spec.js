const { test, expect } = require("@playwright/test");
const {
  dismissBlockingOverlays,
  registerUser,
  todayPtBr,
  uniqueEmail,
} = require("./support/auth");

test.describe("financial collaboration flows", () => {
  test("creates invite, accepts link, shares entry and confirms monthly settlement", async ({
    browser,
  }) => {
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();
    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    try {
      await registerUser(pageA, { email: uniqueEmail("collab-a") });
      await pageA.goto("/account-links/invite", { waitUntil: "networkidle" });
      await pageA.click("#create-invite-btn");

      const inviteUrl =
        (await pageA.locator("#invite-url").textContent())?.trim() || "";
      expect(inviteUrl).toContain("/account-links/accept/");

      await registerUser(pageB, { email: uniqueEmail("collab-b") });
      const originB = new URL(pageB.url()).origin;
      const invitePath = new URL(inviteUrl).pathname;
      await pageB.goto(`${originB}${invitePath}`, { waitUntil: "networkidle" });
      await dismissBlockingOverlays(pageB);
      await expect(pageB).toHaveURL(/\/account-links\/(\d+)/);

      const linkMatch = pageB.url().match(/\/account-links\/(\d+)/);
      expect(linkMatch).not.toBeNull();
      const linkId = linkMatch[1];

      await pageA.goto("/finances", { waitUntil: "networkidle" });
      await dismissBlockingOverlays(pageA);
      await pageA.click("#quick-preset-expense-variable");
      await pageA.fill("#quick-finance-amount", "120,00");
      await pageA.fill('input[name="quick_finance[category]"]', "Moradia");
      await pageA.fill('input[name="quick_finance[occurred_on]"]', todayPtBr());
      await pageA.fill(
        'input[name="quick_finance[description]"]',
        "Conta compartilhada",
      );
      await pageA.check("#quick-finance-share-with-link");
      await pageA.selectOption("#quick-finance-share-link-id", linkId);
      await pageA.click('#quick-finance-form button[type="submit"]');

      await pageA.goto(`/account-links/${linkId}`, {
        waitUntil: "networkidle",
      });
      await expect(pageA.locator("#shared-entries-list")).toBeVisible();
      await expect(
        pageA.locator('button[id^="unshare-entry-"]').first(),
      ).toBeVisible();

      await pageB.goto(`/account-links/${linkId}`, {
        waitUntil: "networkidle",
      });
      await expect(pageB.locator("#shared-entries-list")).toBeVisible();
      await expect(pageB.locator('button[id^="unshare-entry-"]')).toHaveCount(
        0,
      );

      await pageA.click("#shared-confirm-settlement-btn");
      await pageB.click("#shared-confirm-settlement-btn");
      await expect(pageB.locator("#shared-month-confirmation")).toContainText(
        "Status atual: fechado",
      );
    } finally {
      await contextA.close();
      await contextB.close();
    }
  });
});
