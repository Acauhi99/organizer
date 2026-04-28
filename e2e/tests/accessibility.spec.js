const AxeBuilder = require("@axe-core/playwright").default;
const { test, expect } = require("@playwright/test");
const { dismissBlockingOverlays, registerUser, uniqueEmail } = require("./support/auth");

test.describe("accessibility smoke", () => {
  test("critical pages do not have serious or critical axe violations", async ({ page }) => {
    await registerUser(page, { email: uniqueEmail("a11y") });

    await page.goto("/finances", { waitUntil: "networkidle" });
    await dismissBlockingOverlays(page);
    const financesResults = await new AxeBuilder({ page }).analyze();
    assertNoSeriousViolations(financesResults.violations, "/finances");

    await page.goto("/account-links", { waitUntil: "networkidle" });
    await dismissBlockingOverlays(page);
    const linksResults = await new AxeBuilder({ page }).analyze();
    assertNoSeriousViolations(linksResults.violations, "/account-links");
  });
});

function assertNoSeriousViolations(violations, pageName) {
  const blocking = violations.filter(
    (violation) => violation.impact === "critical" || violation.impact === "serious"
  );

  expect(
    blocking,
    `${pageName} possui violacoes axe de impacto serio/critico: ${blocking
      .map((item) => item.id)
      .join(", ")}`
  ).toEqual([]);
}
