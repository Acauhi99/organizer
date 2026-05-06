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

const parseOptionalPositiveInteger = (value) => {
  const parsed = Number.parseInt(`${value || ""}`, 10)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null
}

const hasReachedThreshold = ({element, thresholdPx}) => {
  const remaining = element.scrollHeight - element.scrollTop - element.clientHeight
  return remaining <= thresholdPx
}

const buildLoadPayload = (element) => {
  const payload = {}

  const nextPage = parseOptionalPositiveInteger(element.dataset.nextPage)
  if (nextPage !== null) {
    payload.page = nextPage
  }

  if (typeof element.dataset.status === "string" && element.dataset.status.length > 0) {
    payload.status = element.dataset.status
  }

  return payload
}

const shouldSkipLoad = (state) =>
  state.pending || state.element.dataset.loading === "true" || state.element.dataset.hasMore !== "true"

const clearPendingResetTimer = (state) => {
  if (state.pendingResetTimer === null) {
    return
  }

  window.clearTimeout(state.pendingResetTimer)
  state.pendingResetTimer = null
}

const schedulePendingReset = (state, maybeLoadMore) => {
  clearPendingResetTimer(state)

  state.pendingResetTimer = window.setTimeout(() => {
    state.pending = false
    maybeLoadMore()
  }, state.pendingResetMs)
}

const createState = (hook) => ({
  element: hook.el,
  pushEvent: hook.pushEvent.bind(hook),
  thresholdPx: parseThreshold(hook.el.dataset.thresholdPx),
  pendingResetMs: parsePendingResetMs(hook.el.dataset.pendingResetMs),
  pending: false,
  pendingResetTimer: null,
  cleanup: [],
})

const wireScrollListener = (state, maybeLoadMore) => {
  const onScroll = () => {
    maybeLoadMore()
  }

  state.element.addEventListener("scroll", onScroll, {passive: true})
  state.cleanup.push(() => state.element.removeEventListener("scroll", onScroll))
}

const resetPendingState = (state) => {
  clearPendingResetTimer(state)
  state.pending = false
}

const disposeState = (state) => {
  resetPendingState(state)
  state.cleanup.forEach((cleanup) => cleanup())
  state.cleanup = []
}

const createMaybeLoadMore = (state) => {
  const maybeLoadMore = () => {
    if (shouldSkipLoad(state) || !hasReachedThreshold({element: state.element, thresholdPx: state.thresholdPx})) {
      return
    }

    state.pending = true
    schedulePendingReset(state, maybeLoadMore)
    state.pushEvent(state.element.dataset.event || "load_more_finances", buildLoadPayload(state.element))
  }

  return maybeLoadMore
}

const InfiniteScrollHook = {
  mounted() {
    this.state = createState(this)
    this.maybeLoadMore = createMaybeLoadMore(this.state)

    wireScrollListener(this.state, this.maybeLoadMore)
    this.maybeLoadMore()
  },

  updated() {
    if (!this.state || !this.maybeLoadMore) {
      return
    }

    resetPendingState(this.state)
    this.maybeLoadMore()
  },

  destroyed() {
    if (!this.state) {
      return
    }

    disposeState(this.state)
    this.state = null
    this.maybeLoadMore = null
  },
}

export default InfiniteScrollHook
