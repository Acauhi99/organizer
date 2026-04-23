import {parsePositiveTimeoutMs} from "./number_parsers"

export const scheduleFlashAutoDismiss = () => {
  const flashes = document.querySelectorAll("[data-auto-dismiss-ms]")

  flashes.forEach((flashEl) => {
    if (flashEl.dataset.autoDismissArmed === "true") {
      return
    }

    const timeoutMs = parsePositiveTimeoutMs(flashEl.dataset.autoDismissMs)

    if (timeoutMs === null) {
      return
    }

    flashEl.dataset.autoDismissArmed = "true"

    window.setTimeout(() => {
      if (!document.body.contains(flashEl)) {
        return
      }

      const closeButton = flashEl.querySelector("button[aria-label]")

      if (closeButton) {
        closeButton.click()
      } else {
        flashEl.click()
      }
    }, timeoutMs)
  })
}

export const initializeFlashAutoDismiss = () => {
  scheduleFlashAutoDismiss()

  window.addEventListener("phx:page-loading-stop", () => {
    scheduleFlashAutoDismiss()
  })

  const flashObserver = new MutationObserver(() => {
    scheduleFlashAutoDismiss()
  })

  flashObserver.observe(document.body, {childList: true, subtree: true})
  window.addEventListener("pagehide", () => flashObserver.disconnect(), {once: true})

  return flashObserver
}
