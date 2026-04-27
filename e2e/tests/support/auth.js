const DEFAULT_PASSWORD = "supersecurepassword123";

const uniqueEmail = (prefix = "e2e") => `${prefix}.${Date.now()}.${Math.random().toString(16).slice(2)}@example.com`;

async function dismissBlockingOverlays(page) {
  await page.waitForTimeout(250);

  const onboardingSkip = page.locator("#onboarding-skip-btn");
  if ((await onboardingSkip.count()) > 0 && (await onboardingSkip.first().isVisible())) {
    await onboardingSkip.first().click();
    await page.waitForTimeout(150);
  }

  const notificationLater = page.locator("#notification-permission-later");
  if ((await notificationLater.count()) > 0 && (await notificationLater.first().isVisible())) {
    await notificationLater.first().click();
    await page.waitForTimeout(150);
  }
}

async function registerUser(page, { email = uniqueEmail("register"), password = DEFAULT_PASSWORD } = {}) {
  await page.goto("/users/register", { waitUntil: "networkidle" });
  await page.fill('input[name="user[email]"]', email);
  await page.fill('input[name="user[password]"]', password);
  await page.fill('input[name="user[password_confirmation]"]', password);
  await page.click("#registration_form_password button");
  await page.waitForURL(/\/finances|\/account-links/, { timeout: 20_000 });
  await dismissBlockingOverlays(page);
  return { email, password };
}

async function loginUser(page, { email, password = DEFAULT_PASSWORD } = {}) {
  await page.goto("/users/log-in", { waitUntil: "networkidle" });
  await page.locator("#login_form_password").waitFor({ state: "visible", timeout: 20_000 });
  await page.fill('input[name="user[email]"]', email);
  await page.fill('input[name="user[password]"]', password);
  await page.locator("#login_form_password button").first().click();
  await page.waitForURL(/\/finances|\/account-links/, { timeout: 20_000 });
  await dismissBlockingOverlays(page);
}

async function logoutUser(page) {
  const logoutLink = page.locator('a[href="/users/log-out"]');
  await logoutLink.first().click();
  await page.waitForURL("/", { timeout: 20_000 });
}

function todayPtBr() {
  const now = new Date();
  const day = String(now.getDate()).padStart(2, "0");
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const year = String(now.getFullYear());
  return `${day}/${month}/${year}`;
}

module.exports = {
  DEFAULT_PASSWORD,
  dismissBlockingOverlays,
  loginUser,
  logoutUser,
  registerUser,
  todayPtBr,
  uniqueEmail,
};
