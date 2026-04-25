async function firstElementId(page, selector) {
  const locator = page.locator(selector).first();
  await locator.waitFor({ state: "visible", timeout: 15_000 });
  const id = await locator.getAttribute("id");

  if (!id) {
    throw new Error(`Element ${selector} has no id attribute`);
  }

  return id;
}

function suffixFromId(id, prefix) {
  if (!id.startsWith(prefix)) {
    throw new Error(`Expected id "${id}" to start with "${prefix}"`);
  }

  return id.slice(prefix.length);
}

async function selectFirstNonEmptyOption(page, selectSelector) {
  await page.waitForFunction(
    (selector) => {
      const select = document.querySelector(selector);
      if (!(select instanceof HTMLSelectElement)) {
        return false;
      }

      return Array.from(select.options).some(
        (item) => typeof item.value === "string" && item.value.length > 0
      );
    },
    selectSelector,
    { timeout: 15_000 }
  );

  return page.$eval(selectSelector, (node) => {
    const select = node;
    const option = Array.from(select.options).find(
      (item) => typeof item.value === "string" && item.value.length > 0
    );

    if (!option) {
      return "";
    }

    select.value = option.value;
    select.dispatchEvent(new Event("change", { bubbles: true }));
    return option.value;
  });
}

module.exports = {
  firstElementId,
  selectFirstNonEmptyOption,
  suffixFromId,
};
