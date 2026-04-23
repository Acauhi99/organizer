export const registerScrollToElementListener = () => {
  window.addEventListener("phx:scroll-to-element", (event) => {
    const selector = event?.detail?.selector
    const focusSelector = event?.detail?.focus

    if (typeof selector !== "string" || selector.length === 0) {
      return
    }

    const target = document.querySelector(selector)

    if (!target) {
      return
    }

    target.scrollIntoView({behavior: "smooth", block: "start"})

    if (typeof focusSelector !== "string" || focusSelector.length === 0) {
      return
    }

    window.setTimeout(() => {
      const focusTarget = document.querySelector(focusSelector)

      if (focusTarget instanceof HTMLElement) {
        focusTarget.focus({preventScroll: true})
      }
    }, 180)
  })
}
