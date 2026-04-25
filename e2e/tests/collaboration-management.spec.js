const { test, expect } = require("@playwright/test");
const { dismissBlockingOverlays, logoutUser, registerUser, todayPtBr, uniqueEmail } = require("./support/auth");
const { suffixFromId } = require("./support/ui");

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
      await expect(pageA.locator("#shared-entries-empty-state")).toBeVisible();

      await pageA.goto("/account-links", { waitUntil: "networkidle" });
      await expect(pageA.locator(`#deactivate-link-${linkId}`)).toBeVisible();
      await pageA.click(`#deactivate-link-${linkId}`);
      await expect(pageA.locator(`#account-link-${linkId}`)).toHaveCount(0);
      await expect(pageA.locator("#account-link-empty")).toBeVisible();
    } finally {
      await safeCloseContext(contextA);
      await safeCloseContext(contextB);
    }
  });

  test("shares task with an active link in sync mode", async ({ browser }) => {
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();
    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    try {
      await registerUser(pageA, { email: uniqueEmail("collab-task-a") });
      await pageA.goto("/account-links/invite", { waitUntil: "networkidle" });
      await pageA.click("#create-invite-btn");

      const inviteUrl = (await pageA.locator("#invite-url").textContent())?.trim() || "";
      expect(inviteUrl).toContain("/account-links/accept/");

      await registerUser(pageB, { email: uniqueEmail("collab-task-b") });
      await pageB.goto(normalizeInviteToCurrentOrigin(inviteUrl, pageB.url()), { waitUntil: "networkidle" });
      await dismissBlockingOverlays(pageB);
      await expect(pageB).toHaveURL(/\/account-links\/\d+/);

      const linkId = extractLinkIdFromUrl(pageB.url());
      const runId = Date.now();
      const title = `Tarefa compartilhada E2E ${runId}`;

      await pageA.goto("/tasks", { waitUntil: "networkidle" });
      await dismissBlockingOverlays(pageA);
      await pageA.fill("#quick-task-title", title);
      await pageA.fill('input[name="quick_task[due_on]"]', todayPtBr());
      await pageA.click('#quick-task-form button[type="submit"]');

      const taskCard = pageA.locator("article").filter({ hasText: title }).first();
      await expect(taskCard).toBeVisible();

      const taskEditButtonId = await taskCard
        .locator('button[id^="task-edit-btn-"]')
        .first()
        .getAttribute("id");
      expect(taskEditButtonId).not.toBeNull();
      const taskId = suffixFromId(taskEditButtonId, "task-edit-btn-");

      await pageA.click(`label[for="task-share-check-${taskId}"]`);
      await expect(pageA.locator(`#task-share-link-${taskId}`)).toBeVisible();
      await pageA.selectOption(`#task-share-link-${taskId}`, linkId);
      await pageA.click(`#task-share-btn-${taskId}`);

      await expect(pageA.locator(`#task-share-state-${taskId}`)).toBeVisible();
      await expect(pageA.locator(`#task-share-state-${taskId}`)).toContainText("Atrelada ao compartilhamento");
    } finally {
      await safeCloseContext(contextA);
      await safeCloseContext(contextB);
    }
  });
});
