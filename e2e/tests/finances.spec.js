const { test, expect } = require("@playwright/test");
const { dismissBlockingOverlays, registerUser, todayPtBr, uniqueEmail } = require("./support/auth");
const { firstElementId, suffixFromId } = require("./support/ui");

test.describe("finances module", () => {
  test("creates, edits and deletes a finance entry", async ({ page }) => {
    await registerUser(page, { email: uniqueEmail("finances") });

    await page.goto("/finances", { waitUntil: "networkidle" });
    await dismissBlockingOverlays(page);

    await expect(page.locator("#quick-finance-form")).toBeVisible();
    await page.fill("#quick-finance-amount", "123,45");
    await page.fill('input[name="quick_finance[category]"]', "Supermercado");
    await page.fill('input[name="quick_finance[occurred_on]"]', todayPtBr());
    await page.fill('input[name="quick_finance[description]"]', "Compra semanal");
    await page.click('#quick-finance-form button[type="submit"]');

    const editButtonId = await firstElementId(page, 'button[id^="finance-edit-btn-"]');
    const entryId = suffixFromId(editButtonId, "finance-edit-btn-");

    await page.click(`#${editButtonId}`);
    await expect(page.locator("#finance-edit-modal")).toBeVisible();
    await page.fill(`#finance-description-${entryId}`, "Compra semanal atualizada");
    await page.click(`#finance-edit-form-${entryId} button[type="submit"]`);
    await expect(page.locator("#finance-edit-modal")).toBeHidden();
    await expect(page.locator("body")).toContainText("Compra semanal atualizada");

    await page.click(`#finance-delete-btn-${entryId}`);
    await expect(page.locator(`#finance-delete-btn-${entryId}`)).toHaveCount(0);
  });
});
