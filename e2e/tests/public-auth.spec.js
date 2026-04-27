const { test, expect } = require("@playwright/test");
const { loginUser, logoutUser, registerUser, uniqueEmail } = require("./support/auth");

test.describe("public and auth flows", () => {
  test("home page, registration, login, logout and invalid login", async ({ page }) => {
    await page.goto("/", { waitUntil: "networkidle" });
    await expect(page.locator('#public-home a[href="/users/register"]').first()).toBeVisible();
    await expect(page.locator('#public-home a[href="/users/log-in"]').first()).toBeVisible();

    const credentials = await registerUser(page, {
      email: uniqueEmail("public-auth"),
    });

    await expect(page).toHaveURL(/\/finances|\/account-links/);
    await expect(page.locator("#quick-finance-form")).toBeVisible();

    await logoutUser(page);
    await expect(page).toHaveURL("/");

    await loginUser(page, credentials);
    await expect(page.locator("#quick-finance-form")).toBeVisible();

    await logoutUser(page);
    await page.goto("/users/log-in", { waitUntil: "networkidle" });
    await page.fill('input[name="user[email]"]', credentials.email);
    await page.fill('input[name="user[password]"]', "senha-invalida");
    await page.locator("#login_form_password button").first().click();
    await expect(page.locator("body")).toContainText("E-mail ou senha inválidos");
  });
});
