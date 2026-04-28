const DEFAULT_THRESHOLD_PX = 120

const parseThreshold = (value) => {
  const parsed = Number.parseInt(`${value}`, 10)

  if (!Number.isFinite(parsed) || parsed < 0) {
    return DEFAULT_THRESHOLD_PX
  }

  return parsed
}

const InfiniteScrollHook = {
  mounted() {
    this.thresholdPx = parseThreshold(this.el.dataset.thresholdPx)
    this.pending = false

    this.handleScroll = () => {
      this.maybeLoadMore()
    }

    this.el.addEventListener("scroll", this.handleScroll, {passive: true})
    this.maybeLoadMore()
  },

  updated() {
    this.pending = false
    this.maybeLoadMore()
  },

  destroyed() {
    this.el.removeEventListener("scroll", this.handleScroll)
  },

  maybeLoadMore() {
    if (this.pending || this.el.dataset.loading === "true" || this.el.dataset.hasMore !== "true") {
      return
    }

    const remaining = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight

    if (remaining <= this.thresholdPx) {
      this.pending = true
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
