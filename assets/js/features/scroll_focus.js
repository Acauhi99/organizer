const PHX_SCROLL_EVENT = "phx:scroll-to-element"

const resolveSelector = (value) => (typeof value === "string" && value.length > 0 ? value : null)

const scheduleFocusTarget = (selector) => {
  const focusSelector = resolveSelector(selector)

  if (focusSelector === null) {
    return
  }

  window.setTimeout(() => {
    const focusTarget = document.querySelector(focusSelector)

    if (focusTarget instanceof HTMLElement) {
      focusTarget.focus({preventScroll: true})
    }
  }, 180)
}

const handleScrollToElementEvent = (event) => {
  const selector = resolveSelector(event?.detail?.selector)

  if (selector === null) {
    return
  }

  const target = document.querySelector(selector)

  if (!(target instanceof HTMLElement)) {
    return
  }

  target.scrollIntoView({behavior: "smooth", block: "start"})
  scheduleFocusTarget(event?.detail?.focus)
}

export const registerScrollToElementListener = ({target = window} = {}) => {
  target.addEventListener(PHX_SCROLL_EVENT, handleScrollToElementEvent)

  return () => {
    target.removeEventListener(PHX_SCROLL_EVENT, handleScrollToElementEvent)
  }
}
