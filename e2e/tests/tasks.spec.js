const { test, expect } = require("@playwright/test");
const { dismissBlockingOverlays, registerUser, todayPtBr, uniqueEmail } = require("./support/auth");
const { suffixFromId } = require("./support/ui");

test.describe("tasks module", () => {
  test("creates tasks, uses checklist/details and controls timer", async ({ page }) => {
    const runId = Date.now();
    const timerTitle = `Tarefa timer E2E ${runId}`;
    const checklistTitle = `Tarefa checklist E2E ${runId}`;

    await registerUser(page, { email: uniqueEmail("tasks") });

    await page.goto("/tasks", { waitUntil: "networkidle" });
    await dismissBlockingOverlays(page);

    await expect(page.locator("#quick-task-form")).toBeVisible();

    await page.fill("#quick-task-title", timerTitle);
    await page.fill('input[name="quick_task[due_on]"]', todayPtBr());
    await page.click('#quick-task-form button[type="submit"]');

    const timerCard = page.locator("article").filter({ hasText: timerTitle }).first();
    await expect(timerCard).toBeVisible();

    const timerEditButtonId = await timerCard.locator('button[id^="task-edit-btn-"]').first().getAttribute("id");
    expect(timerEditButtonId).not.toBeNull();
    const timerTaskId = suffixFromId(timerEditButtonId, "task-edit-btn-");

    await timerCard.locator('button[id^="task-status-quick-btn-"]').first().click();
    await expect(page.locator(`#task-focus-task option[value="${timerTaskId}"]`)).toHaveCount(1);

    await page.fill("#quick-task-title", checklistTitle);
    await page.click('#quick-task-form button[type="submit"]');

    const checklistCard = page.locator("article").filter({ hasText: checklistTitle }).first();
    await expect(checklistCard).toBeVisible();

    const checklistEditButtonId = await checklistCard
      .locator('button[id^="task-edit-btn-"]')
      .first()
      .getAttribute("id");
    expect(checklistEditButtonId).not.toBeNull();
    const taskId = suffixFromId(checklistEditButtonId, "task-edit-btn-");

    await page.click(`#task-details-btn-${taskId}`);
    await expect(page.locator("#task-details-modal")).toBeVisible();
    await page.click("#task-details-close-btn");
    await expect(page.locator("#task-details-modal")).toHaveCount(0);

    await page.fill(`#task-checklist-add-input-${taskId}`, "Item checklist E2E");
    await page.click(`#task-checklist-add-btn-${taskId}`);
    await expect(page.locator(`button[id^="task-checklist-toggle-${taskId}-"]`).first()).toBeVisible();

    await page.selectOption("#task-focus-task", timerTaskId);
    await expect(page.locator("#task-focus-task")).toHaveValue(timerTaskId);

    await page.click("#task-focus-start");
    await expect(page.locator("#task-focus-state")).toContainText("Em execução");
    await expect(page.locator("#task-focus-pause")).toBeEnabled();

    await page.click("#task-focus-pause");
    await expect(page.locator("#task-focus-state")).toContainText("Pausado");
    await expect(page.locator("#task-focus-start")).toBeEnabled();

    await page.click("#task-focus-reset");
    await expect(page.locator("#task-focus-state")).toContainText("Pronto");
    await expect(page.locator("#task-focus-remaining")).toContainText("30:00");
  });
});
