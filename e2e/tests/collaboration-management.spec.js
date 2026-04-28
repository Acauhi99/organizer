const { test, expect } = require("@playwright/test");
const { dismissBlockingOverlays, logoutUser, registerUser, todayPtBr, uniqueEmail } = require("./support/auth");

const normalizeInviteToCurrentOrigin = (inviteUrl, pageUrl) => {
  const origin = new URL(pageUrl).origin;
  const path = new URL(inviteUrl).pathname;
  return `${origin}${path}`;
};

const extractLinkIdFromUrl = (url) => {
  const match = url.match(/\/account-links\/(\d+)/);
  if (!match) {
    throw new Error(`Could not extract link id from URL: ${url}`);
  }

  return match[1];
};

const safeCloseContext = async (context) => {
  try {
    await context.close();
  } catch (_) {
    // Ignore close races when the test already timed out or browser was torn down.
  }
};

test.describe("collaboration management journeys", () => {
  test("requires login to accept invite and resumes flow after authentication", async ({ browser }) => {
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();
    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    try {
      await registerUser(pageA, { email: uniqueEmail("collab-redirect-a") });
      await pageA.goto("/account-links/invite", { waitUntil: "networkidle" });
      await pageA.click("#create-invite-btn");

      const inviteUrl = (await pageA.locator("#invite-url").textContent())?.trim() || "";
      expect(inviteUrl).toContain("/account-links/accept/");

      const credentialsB = await registerUser(pageB, { email: uniqueEmail("collab-redirect-b") });
      await logoutUser(pageB);

      await pageB.goto(normalizeInviteToCurrentOrigin(inviteUrl, pageB.url()), { waitUntil: "networkidle" });
      await expect(pageB).toHaveURL(/\/users\/log-in/);
      await expect(pageB.locator("body")).toContainText("aceitar o convite");

      await pageB.fill('input[name="user[email]"]', credentialsB.email);
      await pageB.fill('input[name="user[password]"]', credentialsB.password);
      await pageB.locator("#login_form_password button").first().click();
      await expect(pageB).toHaveURL(/\/account-links\/\d+/);
      await expect(pageB.locator("#shared-entries-list")).toBeVisible();
    } finally {
      await safeCloseContext(contextA);
      await safeCloseContext(contextB);
    }
  });

  test("unshares finance entry and deactivates account link", async ({ browser }) => {
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();
    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    try {
      await registerUser(pageA, { email: uniqueEmail("collab-manage-a") });
      await pageA.goto("/account-links/invite", { waitUntil: "networkidle" });
      await pageA.click("#create-invite-btn");

      const inviteUrl = (await pageA.locator("#invite-url").textContent())?.trim() || "";
      expect(inviteUrl).toContain("/account-links/accept/");

      await registerUser(pageB, { email: uniqueEmail("collab-manage-b") });
      await pageB.goto(normalizeInviteToCurrentOrigin(inviteUrl, pageB.url()), { waitUntil: "networkidle" });
      await dismissBlockingOverlays(pageB);
      await expect(pageB).toHaveURL(/\/account-links\/\d+/);

      const linkId = extractLinkIdFromUrl(pageB.url());

      await pageA.goto("/finances", { waitUntil: "networkidle" });
      await dismissBlockingOverlays(pageA);
      await pageA.fill("#quick-finance-amount", "99,90");
      await pageA.fill('input[name="quick_finance[category]"]', "Utilidades");
      await pageA.fill('input[name="quick_finance[occurred_on]"]', todayPtBr());
      await pageA.fill('input[name="quick_finance[description]"]', "Conta compartilhada para remoção");
      await pageA.check("#quick-finance-share-with-link");
      await pageA.selectOption("#quick-finance-share-link-id", linkId);
      await pageA.click('#quick-finance-form button[type="submit"]');

      await pageA.goto(`/account-links/${linkId}`, { waitUntil: "networkidle" });
      await expect(pageA.locator('button[id^="unshare-entry-"]').first()).toBeVisible();
      await pageA.locator('button[id^="unshare-entry-"]').first().click();
      await expect(pageA.locator("#shared-entry-unshare-confirmation-modal")).toBeVisible();
      await pageA.click("#confirm-unshare-entry-btn");
      await expect(pageA.locator("#shared-entries-empty-state")).toBeVisible();

      await pageA.goto("/account-links", { waitUntil: "networkidle" });
      await expect(pageA.locator(`#deactivate-link-${linkId}`)).toBeVisible();
      await pageA.click(`#deactivate-link-${linkId}`);
      await expect(pageA.locator("#account-link-deactivate-confirmation-modal")).toBeVisible();
      await pageA.click("#confirm-deactivate-link-btn");
      await expect(pageA.locator(`#account-link-${linkId}`)).toHaveCount(0);
      await expect(pageA.locator("#account-link-empty")).toBeVisible();
    } finally {
      await safeCloseContext(contextA);
      await safeCloseContext(contextB);
    }
  });

});
