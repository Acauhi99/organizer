const ONBOARDING_PADDING_PX = 8

const setSpotlightHidden = (spotlight) => {
  spotlight.style.opacity = "0"
}

const setSpotlightPosition = ({spotlight, overlayRect, targetRect}) => {
  spotlight.style.opacity = "1"
  spotlight.style.left = `${targetRect.left - overlayRect.left - ONBOARDING_PADDING_PX}px`
  spotlight.style.top = `${targetRect.top - overlayRect.top - ONBOARDING_PADDING_PX}px`
  spotlight.style.width = `${targetRect.width + ONBOARDING_PADDING_PX * 2}px`
  spotlight.style.height = `${targetRect.height + ONBOARDING_PADDING_PX * 2}px`
}

const resolveTargetElement = (spotlight) => {
  const selector = spotlight.dataset.target
  return typeof selector === "string" ? document.querySelector(selector) : null
}

const syncSpotlight = (state) => {
  if (!(state.spotlight instanceof HTMLElement)) {
    return
  }

  const target = resolveTargetElement(state.spotlight)

  if (!(target instanceof HTMLElement)) {
    setSpotlightHidden(state.spotlight)
    return
  }

  setSpotlightPosition({
    spotlight: state.spotlight,
    overlayRect: state.element.getBoundingClientRect(),
    targetRect: target.getBoundingClientRect(),
  })
}

const createState = (hook) => ({
  element: hook.el,
  spotlight: hook.el.querySelector(".onboarding-spotlight"),
  rafId: null,
  cleanup: [],
})

const scheduleSync = (state) => {
  if (state.rafId !== null) {
    return
  }

  state.rafId = window.requestAnimationFrame(() => {
    state.rafId = null
    syncSpotlight(state)
  })
}

const wireWindowListeners = (state) => {
  const onResize = () => scheduleSync(state)
  const onScroll = () => scheduleSync(state)

  window.addEventListener("resize", onResize, {passive: true})
  window.addEventListener("scroll", onScroll, {passive: true})

  state.cleanup.push(() => window.removeEventListener("resize", onResize))
  state.cleanup.push(() => window.removeEventListener("scroll", onScroll))
}

const disposeState = (state) => {
  if (state.rafId !== null) {
    window.cancelAnimationFrame(state.rafId)
  }

  state.cleanup.forEach((cleanup) => cleanup())
  state.cleanup = []
}

const OnboardingOverlayHook = {
  mounted() {
    this.state = createState(this)
    this.resync = () => scheduleSync(this.state)

    wireWindowListeners(this.state)
    this.resync()
  },

  updated() {
    this.resync?.()
  },

  destroyed() {
    if (!this.state) {
      return
    }

    disposeState(this.state)
    this.state = null
    this.resync = null
  },
}

export default OnboardingOverlayHook
