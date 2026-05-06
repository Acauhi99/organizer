import {parsePositiveTimeoutMs} from "./number_parsers"

const FLASH_SELECTOR = "[data-auto-dismiss-ms]"
const CLOSE_BUTTON_SELECTOR = "button[aria-label]"
const PAGE_LOADING_STOP_EVENT = "phx:page-loading-stop"

const dismissFlashElement = (flashEl) => {
  if (!document.body.contains(flashEl)) {
    return
  }

  const closeButton = flashEl.querySelector(CLOSE_BUTTON_SELECTOR)

  if (closeButton instanceof HTMLElement) {
    closeButton.click()
  } else {
    flashEl.click()
  }
}

const armFlashAutoDismiss = (flashEl) => {
  if (flashEl.dataset.autoDismissArmed === "true") {
    return
  }

  const timeoutMs = parsePositiveTimeoutMs(flashEl.dataset.autoDismissMs)

  if (timeoutMs === null) {
    return
  }

  flashEl.dataset.autoDismissArmed = "true"
  window.setTimeout(() => dismissFlashElement(flashEl), timeoutMs)
}

export const scheduleFlashAutoDismiss = ({root = document} = {}) => {
  root.querySelectorAll(FLASH_SELECTOR).forEach(armFlashAutoDismiss)
}

export const initializeFlashAutoDismiss = ({target = window, root = document.body} = {}) => {
  const scheduleRoot = root instanceof Element ? root : document

  const schedule = () => {
    scheduleFlashAutoDismiss({root: scheduleRoot})
  }

  schedule()

  target.addEventListener(PAGE_LOADING_STOP_EVENT, schedule)

  const flashObserver = new MutationObserver(schedule)
  flashObserver.observe(root, {childList: true, subtree: true})

  const cleanup = () => {
    target.removeEventListener(PAGE_LOADING_STOP_EVENT, schedule)
    flashObserver.disconnect()
  }

  target.addEventListener("pagehide", cleanup, {once: true})

  return cleanup
}
