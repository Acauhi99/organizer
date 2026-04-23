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

const syncSpotlight = (hook) => {
  if (!(hook.spotlight instanceof HTMLElement)) {
    return
  }

  const selector = hook.spotlight.dataset.target
  const target = typeof selector === "string" ? document.querySelector(selector) : null

  if (!(target instanceof HTMLElement)) {
    setSpotlightHidden(hook.spotlight)
    return
  }

  setSpotlightPosition({
    spotlight: hook.spotlight,
    overlayRect: hook.el.getBoundingClientRect(),
    targetRect: target.getBoundingClientRect(),
  })
}

const scheduleSyncSpotlight = (hook) => {
  if (hook.rafId !== null) {
    return
  }

  hook.rafId = window.requestAnimationFrame(() => {
    hook.rafId = null
    syncSpotlight(hook)
  })
}

const OnboardingOverlayHook = {
  mounted() {
    this.spotlight = this.el.querySelector(".onboarding-spotlight")
    this.rafId = null

    this.scheduleSync = () => {
      scheduleSyncSpotlight(this)
    }

    this.onResize = () => this.scheduleSync()
    this.onScroll = () => this.scheduleSync()

    window.addEventListener("resize", this.onResize, {passive: true})
    window.addEventListener("scroll", this.onScroll, {passive: true})
    this.scheduleSync()
  },

  updated() {
    this.scheduleSync?.()
  },

  destroyed() {
    if (this.rafId !== null) {
      window.cancelAnimationFrame(this.rafId)
    }

    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("scroll", this.onScroll)
  },
}

export default OnboardingOverlayHook
