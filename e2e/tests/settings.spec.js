const { test, expect } = require("@playwright/test");
const { loginUser, logoutUser, registerUser, uniqueEmail } = require("./support/auth");

test.describe("account settings", () => {
  test("updates password and allows login with new credentials", async ({ page }) => {
    const credentials = await registerUser(page, { email: uniqueEmail("settings") });
    const newPassword = "supersecurepassword456";

    await page.goto("/users/settings", { waitUntil: "networkidle" });
    await expect(page.locator("#update_password")).toBeVisible();

    await page.fill('input[name="user[password]"]', newPassword);
    await page.fill('input[name="user[password_confirmation]"]', newPassword);
    await page.click("#update_password button");
    await expect(page.locator("body")).toContainText("Senha atualizada com sucesso.");

    await logoutUser(page);
    await loginUser(page, { email: credentials.email, password: newPassword });
    await expect(page).toHaveURL(/\/finances|\/tasks/);
  });
});
