const DEFAULT_THRESHOLD_PX = 120
const DEFAULT_PENDING_RESET_MS = 4000

const parseThreshold = (value) => {
  const parsed = Number.parseInt(`${value}`, 10)

  if (!Number.isFinite(parsed) || parsed < 0) {
    return DEFAULT_THRESHOLD_PX
  }

  return parsed
}

const parsePendingResetMs = (value) => {
  const parsed = Number.parseInt(`${value}`, 10)

  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_PENDING_RESET_MS
  }

  return parsed
}

const InfiniteScrollHook = {
  mounted() {
    this.thresholdPx = parseThreshold(this.el.dataset.thresholdPx)
    this.pendingResetMs = parsePendingResetMs(this.el.dataset.pendingResetMs)
    this.pending = false
    this.pendingResetTimer = null

    this.handleScroll = () => {
      this.maybeLoadMore()
    }

    this.el.addEventListener("scroll", this.handleScroll, {passive: true})
    this.maybeLoadMore()
  },

  updated() {
    this.clearPendingResetTimer()
    this.pending = false
    this.maybeLoadMore()
  },

  destroyed() {
    this.clearPendingResetTimer()
    this.el.removeEventListener("scroll", this.handleScroll)
  },

  clearPendingResetTimer() {
    if (this.pendingResetTimer) {
      window.clearTimeout(this.pendingResetTimer)
      this.pendingResetTimer = null
    }
  },

  schedulePendingReset() {
    this.clearPendingResetTimer()

    this.pendingResetTimer = window.setTimeout(() => {
      this.pending = false
      this.maybeLoadMore()
    }, this.pendingResetMs)
  },

  maybeLoadMore() {
    if (this.pending || this.el.dataset.loading === "true" || this.el.dataset.hasMore !== "true") {
      return
    }

    const remaining = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight

    if (remaining <= this.thresholdPx) {
      this.pending = true
      this.schedulePendingReset()
      const payload = {}

      const nextPageRaw = this.el.dataset.nextPage
      const nextPage =
        typeof nextPageRaw === "string" && nextPageRaw.length > 0 ? Number.parseInt(nextPageRaw, 10) : NaN

      if (Number.isFinite(nextPage) && nextPage > 0) {
        payload.page = nextPage
      }

      if (typeof this.el.dataset.status === "string" && this.el.dataset.status.length > 0) {
        payload.status = this.el.dataset.status
      }

      this.pushEvent(this.el.dataset.event || "load_more_finances", payload)
    }
  },
}

export default InfiniteScrollHook
