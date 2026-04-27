const { test, expect, request } = require("@playwright/test");
const { registerUser, uniqueEmail } = require("./support/auth");

test.describe("api v1 authenticated smoke", () => {
  test("creates and lists resources across all API modules", async ({ page, baseURL }) => {
    await registerUser(page, { email: uniqueEmail("api") });

    const storageState = await page.context().storageState();
    const api = await request.newContext({ baseURL, storageState });

    try {
      const financeCreate = await api.post("/api/v1/finance-entries", {
        data: {
          finance_entry: {
            kind: "income",
            amount_cents: 15000,
            category: "Freelance",
            occurred_on: new Date().toISOString().slice(0, 10),
          },
        },
      });
      expect(financeCreate.ok()).toBeTruthy();
      const financePayload = await financeCreate.json();
      expect(financePayload.data.category).toBe("Freelance");

      const fixedCreate = await api.post("/api/v1/fixed-costs", {
        data: {
          fixed_cost: {
            name: "Internet API E2E",
            amount_cents: 8900,
            billing_day: 10,
            starts_on: new Date().toISOString().slice(0, 10),
          },
        },
      });
      expect(fixedCreate.ok()).toBeTruthy();
      const fixedPayload = await fixedCreate.json();
      expect(fixedPayload.data.name).toBe("Internet API E2E");

      const dateCreate = await api.post("/api/v1/important-dates", {
        data: {
          important_date: {
            title: "Data API E2E",
            category: "personal",
            date: new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10),
          },
        },
      });
      expect(dateCreate.ok()).toBeTruthy();
      const datePayload = await dateCreate.json();
      expect(datePayload.data.title).toBe("Data API E2E");
    } finally {
      await api.dispose();
    }
  });
});
