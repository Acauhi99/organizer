const { test, expect } = require("@playwright/test");
const { DEFAULT_PASSWORD, dismissBlockingOverlays, registerUser, uniqueEmail } = require("./support/auth");

async function registerUserWithoutOverlayDismiss(
  page,
  { email = uniqueEmail("experience"), password = DEFAULT_PASSWORD } = {}
) {
  await page.goto("/users/register", { waitUntil: "networkidle" });
  await page.fill('input[name="user[email]"]', email);
  await page.fill('input[name="user[password]"]', password);
  await page.fill('input[name="user[password_confirmation]"]', password);
  await page.click("#registration_form_password button");
  await page.waitForURL(/\/finances|\/account-links/, { timeout: 20_000 });

  return { email, password };
}

async function dismissNotificationPromptWhenVisible(page) {
  const laterButton = page.locator("#notification-permission-later");

  for (let attempt = 0; attempt < 10; attempt += 1) {
    if ((await laterButton.count()) > 0 && (await laterButton.first().isVisible())) {
      await laterButton.first().click();
      return;
    }

    await page.waitForTimeout(120);
  }
}

test.describe("transversal experience journeys", () => {
  test("shows onboarding on first authenticated experience and persists skip", async ({ page }) => {
    await registerUserWithoutOverlayDismiss(page, { email: uniqueEmail("onboarding") });

    await expect(page.locator("#onboarding-overlay")).toBeVisible();
    await expect(page.locator("#onboarding-title")).toContainText("Bem-vindo");

    await page.click("#onboarding-next-btn");
    await expect(page.locator("#onboarding-title")).toContainText("Lançamento Rápido");

    await page.click("#onboarding-prev-btn");
    await expect(page.locator("#onboarding-title")).toContainText("Bem-vindo");

    await page.click("#onboarding-skip-btn");
    await expect(page.locator("#onboarding-overlay")).toHaveCount(0);

    await dismissBlockingOverlays(page);
    await page.reload({ waitUntil: "networkidle" });
    await expect(page.locator("#onboarding-overlay")).toHaveCount(0);
  });

  test("supports Alt+B keyboard shortcut for quick finance focus", async ({ page }) => {
    await registerUser(page, { email: uniqueEmail("shortcuts") });

    await page.goto("/finances", { waitUntil: "networkidle" });
    await dismissBlockingOverlays(page);
    await dismissNotificationPromptWhenVisible(page);

    await page.keyboard.press("Alt+b");
    await expect(page.locator("#quick-finance-amount")).toBeFocused();
  });
});
