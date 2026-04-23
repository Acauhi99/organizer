// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/organizer"
import topbar from "../vendor/topbar"

const BULK_DEFAULT_SELECTORS = {
  preview: "#bulk-preview-btn",
  import: "#bulk-import-btn",
  fixAll: "#bulk-fix-all-btn",
}

const BULK_PREFIX_TEMPLATES = [
  {prefixes: ["t", "ta", "tar", "task", "tarefa"], value: () => "tarefa: "},
  {
    prefixes: ["f", "fi", "fin", "finance", "financeiro"],
    value: (today) =>
      `financeiro: tipo=despesa | natureza=variavel | pagamento=debito | valor=0 | categoria=geral | data=${today}`,
  },
  {
    prefixes: ["r", "rec", "receita", "income"],
    value: (today) => `financeiro: tipo=receita | valor=0 | categoria=geral | data=${today}`,
  },
  {
    prefixes: ["d", "des", "despesa", "expense"],
    value: (today) =>
      `financeiro: tipo=despesa | natureza=variavel | pagamento=debito | valor=0 | categoria=geral | data=${today}`,
  },
  {prefixes: ["m", "me", "meta", "goal"], value: () => "meta: "},
]

const hasPrimaryModifier = (event) => event.ctrlKey || event.metaKey

const resolveBulkShortcutAction = (event) => {
  if (hasPrimaryModifier(event) && !event.shiftKey && event.key === "Enter") {
    return "preview"
  }

  const normalizedKey = typeof event.key === "string" ? event.key.toLowerCase() : ""

  if (hasPrimaryModifier(event) && event.shiftKey && normalizedKey === "f") {
    return "fixAll"
  }

  if (hasPrimaryModifier(event) && event.shiftKey && normalizedKey === "i") {
    return "import"
  }

  if (event.key === "Tab" && !event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey) {
    return "autocomplete"
  }

  return null
}

const currentLineBounds = (value, cursor) => {
  const lineStart = value.lastIndexOf("\n", cursor - 1) + 1
  const lineEndIndex = value.indexOf("\n", cursor)
  const lineEnd = lineEndIndex === -1 ? value.length : lineEndIndex

  return {lineStart, lineEnd}
}

const findBulkTemplate = (trimmedLine) => {
  const today = new Date().toISOString().slice(0, 10)

  const match = BULK_PREFIX_TEMPLATES.find((entry) =>
    entry.prefixes.some((prefix) => trimmedLine === prefix || trimmedLine.startsWith(prefix))
  )

  if (!match) {
    return null
  }

  return match.value(today)
}

const FIELD_PATTERNS = [
  "prioridade", "priority",
  "status",
  "horizonte", "horizon",
  "tipo", "kind",
  "natureza", "expense_profile",
  "pagamento", "payment_method",
]

const computeFieldAutocomplete = ({value, start, end}) => {
  if (typeof start !== "number" || typeof end !== "number" || start !== end) {
    return null
  }

  const source = value || ""
  const {lineStart, lineEnd} = currentLineBounds(source, start)
  const currentLine = source.slice(lineStart, lineEnd)

  // Detect cursor after campo=prefix pattern
  const beforeCursor = currentLine.slice(0, start - lineStart)
  const fieldMatch = beforeCursor.match(/\b([a-z_]+)=([a-zA-Z]*)$/i)

  if (!fieldMatch) return null

  const fieldName = fieldMatch[1].toLowerCase()
  const prefix = fieldMatch[2]

  if (!FIELD_PATTERNS.includes(fieldName)) return null

  return {fieldName, prefix, lineStart, lineEnd, beforeCursor}
}

const computeTypeAutocomplete = ({value, start, end}) => {
  if (typeof start !== "number" || typeof end !== "number" || start !== end) {
    return null
  }

  const source = value || ""
  const {lineStart, lineEnd} = currentLineBounds(source, start)
  const currentLine = source.slice(lineStart, lineEnd)
  const trimmedLine = currentLine.trim().toLowerCase()

  if (trimmedLine === "" || currentLine.includes(":")) {
    return null
  }

  const template = findBulkTemplate(trimmedLine)

  if (!template) {
    return null
  }

  return {
    nextValue: `${source.slice(0, lineStart)}${template}${source.slice(lineEnd)}`,
    cursor: lineStart + template.length,
  }
}

const parsePositiveTimeoutMs = (value) => {
  const timeoutMs = Number(value)

  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    return null
  }

  return timeoutMs
}

const TASK_FOCUS_PRESET_MINUTES = Array.from({length: 12}, (_, index) => (index + 1) * 15)
const TASK_FOCUS_DEFAULT_MINUTES = 30
const TASK_FOCUS_MIN_MINUTES = 1
const TASK_FOCUS_MAX_MINUTES = 600
const TASK_FOCUS_DEFAULT_STATUS = "idle"

const clamp = (value, min, max) => Math.min(max, Math.max(min, value))

const parseTaskFocusMinutes = (value) => {
  const parsedValue = Number.parseInt(`${value}`, 10)

  if (!Number.isFinite(parsedValue)) {
    return null
  }

  return clamp(parsedValue, TASK_FOCUS_MIN_MINUTES, TASK_FOCUS_MAX_MINUTES)
}

const normalizeTaskFocusMinutes = (value, fallback = TASK_FOCUS_DEFAULT_MINUTES) => {
  const parsedValue = parseTaskFocusMinutes(value)
  return parsedValue === null ? fallback : parsedValue
}

const taskFocusIsPresetMinute = (value) => {
  const parsedValue = Number.parseInt(`${value}`, 10)
  return TASK_FOCUS_PRESET_MINUTES.includes(parsedValue)
}

const taskFocusTotalSeconds = (minutes) => normalizeTaskFocusMinutes(minutes) * 60

const taskFocusDefaultState = () => ({
  taskId: "",
  taskLabel: "",
  durationMinutes: TASK_FOCUS_DEFAULT_MINUTES,
  remainingSeconds: taskFocusTotalSeconds(TASK_FOCUS_DEFAULT_MINUTES),
  status: TASK_FOCUS_DEFAULT_STATUS,
  endsAtMs: null,
  notified: false,
})

const normalizeTaskFocusState = (payload) => {
  if (!payload || typeof payload !== "object") {
    return taskFocusDefaultState()
  }

  const durationMinutes = normalizeTaskFocusMinutes(payload.durationMinutes)
  const totalSeconds = taskFocusTotalSeconds(durationMinutes)
  const statuses = ["idle", "running", "paused", "finished"]
  const status = statuses.includes(payload.status) ? payload.status : TASK_FOCUS_DEFAULT_STATUS
  const remainingRaw = Number(payload.remainingSeconds)
  const remainingSeconds = Number.isFinite(remainingRaw)
    ? clamp(Math.floor(remainingRaw), 0, totalSeconds)
    : totalSeconds

  const taskId = typeof payload.taskId === "string" ? payload.taskId : ""
  const taskLabel = typeof payload.taskLabel === "string" ? payload.taskLabel : ""

  let normalized = {
    taskId,
    taskLabel,
    durationMinutes,
    remainingSeconds,
    status,
    endsAtMs: Number.isFinite(payload.endsAtMs) ? payload.endsAtMs : null,
    notified: payload.notified === true,
  }

  if (normalized.status === "running" && normalized.endsAtMs === null) {
    normalized = {...normalized, status: "paused"}
  }

  if (normalized.status === "finished") {
    normalized = {...normalized, remainingSeconds: 0, endsAtMs: null}
  }

  if (normalized.status === "idle") {
    normalized = {
      ...normalized,
      remainingSeconds:
        normalized.remainingSeconds === 0 ? totalSeconds : normalized.remainingSeconds,
      endsAtMs: null,
    }
  }

  return normalized
}

const formatRemainingClock = (seconds) => {
  const safeSeconds = Number.isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0
  const minutes = Math.floor(safeSeconds / 60)
  const remainder = safeSeconds % 60

  return `${String(minutes).padStart(2, "0")}:${String(remainder).padStart(2, "0")}`
}

const browserSupportsNotifications = () => typeof window !== "undefined" && "Notification" in window

const resolveNotificationStatusLabel = () => {
  if (!browserSupportsNotifications()) {
    return "Este navegador não suporta notificações."
  }

  if (Notification.permission === "granted") {
    return "Notificações ativas para alertar no término do timer."
  }

  if (Notification.permission === "denied") {
    return "Notificações bloqueadas no navegador."
  }

  return "Permita notificações para receber alerta ao concluir o time box."
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const hooks = {
  ...colocatedHooks,
  TaskFocusTimer: {
    mounted() {
      this.storageKey = this.el.dataset.storageKey || "organizer:task-focus-timer"
      this.intervalId = null
      this.startWithoutTask = false
      this.pendingSyncedTask = null

      this.handleClick = (event) => {
        const target = event.target

        if (!(target instanceof HTMLElement)) {
          return
        }

        if (target.id === "task-focus-start") {
          event.preventDefault()
          this.startTimer()
        } else if (target.id === "task-focus-pause") {
          event.preventDefault()
          this.pauseTimer()
        } else if (target.id === "task-focus-reset") {
          event.preventDefault()
          this.resetTimer()
        } else if (target.id === "task-focus-apply-custom") {
          event.preventDefault()
          const {durationCustomInput} = this.elements()
          this.updateCustomDuration(durationCustomInput?.value)
        } else if (target.id === "task-focus-request-notification") {
          event.preventDefault()
          this.requestNotificationPermission()
        }
      }

      this.handleChange = (event) => {
        const target = event.target

        if (!(target instanceof HTMLElement)) {
          return
        }

        if (target.id === "task-focus-task") {
          this.updateTaskSelection(target.value)
        }

        if (target.id === "task-focus-duration") {
          this.updateDuration(target.value)
        }

        if (target.id === "task-focus-duration-custom") {
          this.updateCustomDuration(target.value)
        }
      }

      this.handleKeyDown = (event) => {
        if (event.key !== "Enter") {
          return
        }

        const target = event.target

        if (!(target instanceof HTMLElement) || target.id !== "task-focus-duration-custom") {
          return
        }

        event.preventDefault()
        this.updateCustomDuration(target.value)
      }

      this.el.addEventListener("click", this.handleClick)
      this.el.addEventListener("change", this.handleChange)
      this.el.addEventListener("keydown", this.handleKeyDown)
      this.handleEvent("task_focus_sync_target", (payload) => this.syncTaskFromServer(payload))

      this.state = this.loadState()
      this.syncStateAfterMount()
      this.syncSelectorsFromState()
      this.applyPendingSyncedTask()
      this.ensureTickerState()
      this.render()
    },

    updated() {
      this.syncSelectorsFromState()
      this.applyPendingSyncedTask()
      this.render()
    },

    destroyed() {
      this.stopTicker()

      this.el.removeEventListener("click", this.handleClick)
      this.el.removeEventListener("change", this.handleChange)
      this.el.removeEventListener("keydown", this.handleKeyDown)
    },

    elements() {
      return {
        taskSelect: this.el.querySelector("#task-focus-task"),
        durationSelect: this.el.querySelector("#task-focus-duration"),
        durationCustomInput: this.el.querySelector("#task-focus-duration-custom"),
        startButton: this.el.querySelector("#task-focus-start"),
        pauseButton: this.el.querySelector("#task-focus-pause"),
        resetButton: this.el.querySelector("#task-focus-reset"),
        applyCustomButton: this.el.querySelector("#task-focus-apply-custom"),
        stateBadge: this.el.querySelector("#task-focus-state"),
        remaining: this.el.querySelector("#task-focus-remaining"),
        progressBar: this.el.querySelector("#task-focus-progress"),
        notificationState: this.el.querySelector("#task-focus-notification-state"),
        requestNotificationButton: this.el.querySelector("#task-focus-request-notification"),
      }
    },

    loadState() {
      try {
        const rawState = window.localStorage.getItem(this.storageKey)

        if (!rawState) {
          return taskFocusDefaultState()
        }

        return normalizeTaskFocusState(JSON.parse(rawState))
      } catch (_) {
        return taskFocusDefaultState()
      }
    },

    persistState() {
      try {
        window.localStorage.setItem(this.storageKey, JSON.stringify(this.state))
      } catch (_) {}
    },

    totalSeconds() {
      return taskFocusTotalSeconds(this.state.durationMinutes)
    },

    syncStateAfterMount() {
      if (this.state.status !== "running") {
        return
      }

      this.updateRemainingFromClock()

      if (this.state.remainingSeconds <= 0) {
        this.completeTimer()
      }
    },

    syncTaskFromServer(payload) {
      const taskIdRaw = payload?.task_id
      const taskTitle = typeof payload?.task_title === "string" ? payload.task_title : ""
      const taskId =
        taskIdRaw === undefined || taskIdRaw === null ? "" : String(taskIdRaw)

      if (taskId.length === 0) {
        return
      }

      if (
        this.state.status === "running" &&
        this.state.taskId.length > 0 &&
        this.state.taskId !== taskId
      ) {
        return
      }

      this.pendingSyncedTask = {taskId, taskTitle}
      this.applyPendingSyncedTask()
      this.render()
    },

    applyPendingSyncedTask() {
      if (!this.pendingSyncedTask) {
        return
      }

      const {taskSelect} = this.elements()

      if (!taskSelect) {
        return
      }

      const matchedOption = Array.from(taskSelect.options).find(
        (option) => option.value === this.pendingSyncedTask.taskId
      )

      if (!matchedOption) {
        return
      }

      this.state.taskId = matchedOption.value
      this.state.taskLabel =
        this.pendingSyncedTask.taskTitle || matchedOption.textContent?.trim() || ""
      this.startWithoutTask = false
      this.pendingSyncedTask = null
      taskSelect.value = this.state.taskId
      this.persistState()
    },

    syncSelectorsFromState() {
      const {taskSelect, durationSelect, durationCustomInput} = this.elements()

      if (durationSelect) {
        durationSelect.value = taskFocusIsPresetMinute(this.state.durationMinutes)
          ? String(this.state.durationMinutes)
          : ""
      }

      if (durationCustomInput) {
        durationCustomInput.value = String(this.state.durationMinutes)
      }

      if (!taskSelect) {
        return
      }

      const nonEmptyOptions = Array.from(taskSelect.options).filter(
        (option) => typeof option.value === "string" && option.value.length > 0
      )

      if (!this.state.taskId && this.state.status !== "running" && nonEmptyOptions.length > 0) {
        const firstOption = nonEmptyOptions[0]
        this.state.taskId = firstOption.value
        this.state.taskLabel = firstOption.textContent?.trim() || ""
        this.persistState()
      }

      const optionByValue = Array.from(taskSelect.options).find(
        (option) => option.value === this.state.taskId
      )

      if (optionByValue) {
        taskSelect.value = this.state.taskId

        if (!this.state.taskLabel) {
          this.state.taskLabel = optionByValue.textContent?.trim() || ""
        }
      } else if (this.state.status !== "running") {
        const fallbackOption = nonEmptyOptions[0]

        if (fallbackOption) {
          this.state.taskId = fallbackOption.value
          this.state.taskLabel = fallbackOption.textContent?.trim() || ""
          taskSelect.value = fallbackOption.value
          this.persistState()
        } else {
          this.state.taskId = ""
          this.state.taskLabel = ""
          taskSelect.value = ""
          this.persistState()
        }
      }
    },

    setStateBadge(status) {
      const {stateBadge} = this.elements()

      if (!stateBadge) {
        return
      }

      const badgeMap = {
        idle: {
          label: this.startWithoutTask ? "Selecione uma tarefa" : "Pronto",
          classes: "badge badge-sm border-base-content/24 bg-base-100 text-base-content/80",
        },
        running: {
          label: "Em execução",
          classes: "badge badge-sm border-info/35 bg-info/14 text-info-content",
        },
        paused: {
          label: "Pausado",
          classes: "badge badge-sm border-warning/40 bg-warning/14 text-warning-content",
        },
        finished: {
          label: "Tempo concluído",
          classes: "badge badge-sm border-success/40 bg-success/14 text-success-content",
        },
      }

      const badge = badgeMap[status] || badgeMap.idle
      stateBadge.className = badge.classes
      stateBadge.textContent = badge.label
    },

    updateTaskSelection(taskId) {
      if (this.state.status === "running") {
        this.syncSelectorsFromState()
        return
      }

      const {taskSelect} = this.elements()
      const selectedOption = taskSelect?.selectedOptions?.[0]

      this.state.taskId = typeof taskId === "string" ? taskId : ""
      this.state.taskLabel = this.state.taskId
        ? selectedOption?.textContent?.trim() || ""
        : ""

      this.startWithoutTask = false
      this.persistState()
      this.render()
    },

    updateDuration(durationValue) {
      if (this.state.status === "running") {
        this.syncSelectorsFromState()
        return
      }

      const durationMinutes = normalizeTaskFocusMinutes(
        durationValue,
        this.state.durationMinutes || TASK_FOCUS_DEFAULT_MINUTES
      )

      this.state.durationMinutes = durationMinutes
      this.state.remainingSeconds = taskFocusTotalSeconds(durationMinutes)
      this.state.status = TASK_FOCUS_DEFAULT_STATUS
      this.state.endsAtMs = null
      this.state.notified = false
      this.startWithoutTask = false

      this.persistState()
      this.render()
    },

    updateCustomDuration(durationValue) {
      if (this.state.status === "running") {
        this.syncSelectorsFromState()
        this.render()
        return
      }

      const customDuration = parseTaskFocusMinutes(durationValue)

      if (customDuration === null) {
        this.syncSelectorsFromState()
        this.render()
        return
      }

      this.updateDuration(customDuration)
    },

    startTimer() {
      if (this.state.status === "running") {
        return
      }

      if (!this.state.taskId) {
        this.startWithoutTask = true
        this.render()
        return
      }

      const totalSeconds = this.totalSeconds()
      const baseRemaining =
        this.state.status === "finished" || this.state.remainingSeconds <= 0
          ? totalSeconds
          : this.state.remainingSeconds

      this.state.remainingSeconds = clamp(baseRemaining, 0, totalSeconds)
      this.state.status = "running"
      this.state.endsAtMs = Date.now() + this.state.remainingSeconds * 1_000
      this.state.notified = false
      this.startWithoutTask = false

      this.persistState()
      this.ensureTickerState()
      this.render()
    },

    pauseTimer() {
      if (this.state.status !== "running") {
        return
      }

      this.updateRemainingFromClock()
      this.state.status = "paused"
      this.state.endsAtMs = null

      this.persistState()
      this.ensureTickerState()
      this.render()
    },

    resetTimer() {
      this.state.status = TASK_FOCUS_DEFAULT_STATUS
      this.state.remainingSeconds = this.totalSeconds()
      this.state.endsAtMs = null
      this.state.notified = false
      this.startWithoutTask = false

      this.persistState()
      this.ensureTickerState()
      this.render()
    },

    ensureTickerState() {
      if (this.state.status === "running") {
        this.startTicker()
      } else {
        this.stopTicker()
      }
    },

    startTicker() {
      if (this.intervalId !== null) {
        return
      }

      this.intervalId = window.setInterval(() => {
        if (this.state.status !== "running") {
          this.stopTicker()
          return
        }

        this.updateRemainingFromClock()

        if (this.state.remainingSeconds <= 0) {
          this.completeTimer()
        } else {
          this.render()
        }
      }, 250)
    },

    stopTicker() {
      if (this.intervalId === null) {
        return
      }

      window.clearInterval(this.intervalId)
      this.intervalId = null
    },

    updateRemainingFromClock() {
      const endsAt = Number(this.state.endsAtMs)

      if (!Number.isFinite(endsAt)) {
        return
      }

      const nextRemaining = Math.max(0, Math.ceil((endsAt - Date.now()) / 1_000))
      this.state.remainingSeconds = nextRemaining
    },

    completeTimer() {
      this.stopTicker()
      this.state.status = "finished"
      this.state.remainingSeconds = 0
      this.state.endsAtMs = null

      if (!this.state.notified) {
        this.notifyCompletion()
        this.state.notified = true
      }

      this.persistState()
      this.render()
    },

    notifyCompletion() {
      if (!browserSupportsNotifications() || Notification.permission !== "granted") {
        return
      }

      const taskLabel = this.state.taskLabel || "sua tarefa"
      const notification = new Notification("Time box concluído", {
        body: `O tempo para ${taskLabel} terminou.`,
        tag: `task-focus:${this.state.taskId || "general"}`,
      })

      window.setTimeout(() => {
        notification.close?.()
      }, 10_000)
    },

    requestNotificationPermission() {
      if (!browserSupportsNotifications()) {
        this.render()
        return
      }

      if (Notification.permission === "granted" || Notification.permission === "denied") {
        this.render()
        return
      }

      Notification.requestPermission()
        .then(() => {
          this.render()
        })
        .catch(() => {
          this.render()
        })
    },

    render() {
      const {
        taskSelect,
        durationSelect,
        durationCustomInput,
        startButton,
        pauseButton,
        resetButton,
        applyCustomButton,
        remaining,
        progressBar,
        notificationState,
        requestNotificationButton,
      } = this.elements()

      const status = this.state.status
      const totalSeconds = this.totalSeconds()
      const remainingSeconds = clamp(this.state.remainingSeconds, 0, totalSeconds)
      const completionRatio = totalSeconds === 0 ? 0 : (totalSeconds - remainingSeconds) / totalSeconds
      const completionPercent = Math.round(clamp(completionRatio * 100, 0, 100))
      const notificationLabel = resolveNotificationStatusLabel()
      const notificationSupported = browserSupportsNotifications()

      this.state.remainingSeconds = remainingSeconds
      this.setStateBadge(status)

      if (remaining) {
        remaining.textContent = formatRemainingClock(remainingSeconds)
      }

      if (notificationState) {
        notificationState.textContent = notificationLabel
      }

      if (progressBar) {
        const progressClasses = {
          idle: "h-full rounded-full bg-base-content/25 transition-all duration-500",
          running: "h-full rounded-full bg-info transition-all duration-500",
          paused: "h-full rounded-full bg-warning transition-all duration-500",
          finished: "h-full rounded-full bg-success transition-all duration-500",
        }

        progressBar.className = progressClasses[status] || progressClasses.idle
        progressBar.style.width = `${completionPercent}%`
      }

      if (startButton) {
        startButton.disabled = status === "running" || this.state.taskId.length === 0
      }

      if (pauseButton) {
        pauseButton.disabled = status !== "running"
      }

      if (resetButton) {
        resetButton.disabled = status === "idle" && remainingSeconds === totalSeconds
      }

      if (taskSelect) {
        taskSelect.disabled = status === "running"
      }

      if (durationSelect) {
        durationSelect.disabled = status === "running"
      }

      if (durationCustomInput) {
        durationCustomInput.disabled = status === "running"
      }

      if (applyCustomButton) {
        applyCustomButton.disabled = status === "running"
      }

      if (requestNotificationButton) {
        requestNotificationButton.hidden =
          !notificationSupported || Notification.permission === "granted"
        requestNotificationButton.disabled = Notification.permission === "denied"
      }
    },
  },
  OnboardingOverlay: {
    mounted() {
      this.spotlight = this.el.querySelector(".onboarding-spotlight")
      this.rafId = null

      this.syncSpotlight = () => {
        if (!(this.spotlight instanceof HTMLElement)) {
          return
        }

        const selector = this.spotlight.dataset.target
        const target = typeof selector === "string" ? document.querySelector(selector) : null

        if (!(target instanceof HTMLElement)) {
          this.spotlight.style.opacity = "0"
          return
        }

        const overlayRect = this.el.getBoundingClientRect()
        const targetRect = target.getBoundingClientRect()
        const padding = 8

        this.spotlight.style.opacity = "1"
        this.spotlight.style.left = `${targetRect.left - overlayRect.left - padding}px`
        this.spotlight.style.top = `${targetRect.top - overlayRect.top - padding}px`
        this.spotlight.style.width = `${targetRect.width + padding * 2}px`
        this.spotlight.style.height = `${targetRect.height + padding * 2}px`
      }

      this.scheduleSync = () => {
        if (this.rafId !== null) {
          return
        }

        this.rafId = window.requestAnimationFrame(() => {
          this.rafId = null
          this.syncSpotlight()
        })
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
  },
  BulkCaptureEditor: {
    mounted() {
      this.previewSelector = this.el.dataset.previewSelector || BULK_DEFAULT_SELECTORS.preview
      this.importSelector = this.el.dataset.importSelector || BULK_DEFAULT_SELECTORS.import
      this.fixAllSelector = this.el.dataset.fixAllSelector || BULK_DEFAULT_SELECTORS.fixAll

      this.validationTimeout = null
      this.previousValue = ""

      this.onKeyDown = (event) => {
        const action = resolveBulkShortcutAction(event)

        if (!action) {
          return
        }

        if (action === "autocomplete") {
          // Try field value autocomplete first
          const fieldContext = computeFieldAutocomplete({
            value: this.el.value,
            start: this.el.selectionStart,
            end: this.el.selectionEnd,
          })

          if (fieldContext) {
            event.preventDefault()
            this.pushEvent("complete_field_value", {
              field: fieldContext.fieldName,
              prefix: fieldContext.prefix,
            })
              .then((reply) => {
                this.applyFieldAutocompleteResult(fieldContext, reply?.completed)
              })
              .catch(() => {})
            return
          }

          // Fall back to type autocomplete
          if (this.applyTypeAutocomplete()) {
            event.preventDefault()
          }

          return
        }

        const selectorByAction = {
          preview: this.previewSelector,
          fixAll: this.fixAllSelector,
          import: this.importSelector,
        }

        event.preventDefault()
        this.clickSelector(selectorByAction[action])
      }

      this.onInput = (event) => {
        // Real-time validation as user types — debounced to 300ms to prevent
        // excessive validation calls on every keystroke (Requirements 6.1, 11.5)
        clearTimeout(this.validationTimeout)

        if (event.target.value !== this.previousValue) {
          this.previousValue = event.target.value

          this.validationTimeout = setTimeout(() => {
            this.validateCurrentLines()
          }, 300)
        }
      }

      this.el.addEventListener("keydown", this.onKeyDown)
      this.el.addEventListener("input", this.onInput)

      this.applyFieldAutocompleteResult = (context, completed) => {
        const ctx = context
        if (!ctx) return
        if (!completed) return

        const source = this.el.value
        const prefix = ctx.prefix
        const prefixStart = ctx.lineStart + ctx.beforeCursor.length - prefix.length

        const nextValue =
          source.slice(0, prefixStart) +
          completed +
          source.slice(prefixStart + prefix.length)

        this.el.value = nextValue
        const newCursor = prefixStart + completed.length
        this.el.setSelectionRange(newCursor, newCursor)
        this.el.dispatchEvent(new Event("input", {bubbles: true}))
      }

      this.confidenceIndicators = {}

      this.handleBulkLineValidated = (payload) => {
        const {index, confidence_level} = payload
        if (confidence_level === "ignored") {
          delete this.confidenceIndicators[index]
        } else {
          this.confidenceIndicators[index] = confidence_level
        }
        this.renderConfidenceOverlay()
      }
    },

    destroyed() {
      clearTimeout(this.validationTimeout)
      this.el.removeEventListener("keydown", this.onKeyDown)
      this.el.removeEventListener("input", this.onInput)
      // Remove overlay if exists
      const overlay = document.getElementById("bulk-confidence-overlay")
      if (overlay) overlay.remove()
    },

    validateCurrentLines() {
      // Só envia linhas alteradas desde a última validação
      const lines = this.el.value.split(/\r?\n/)
      if (!this._lastValidatedLines) {
        this._lastValidatedLines = []
      }

      lines.forEach((line, index) => {
        const prev = this._lastValidatedLines[index] || ""
        if (line !== prev) {
          if (line.trim().length > 0) {
            this.pushEvent("validate_bulk_line", {
              line: line,
              index: index + 1,
            })
              .then((reply) => {
                if (reply) {
                  this.handleBulkLineValidated(reply)
                }
              })
              .catch(() => {})
          } else {
            this.handleBulkLineValidated({
              index: index + 1,
              confidence_level: "ignored",
            })
          }
        }
      })
      // Atualiza snapshot
      this._lastValidatedLines = lines.slice()
    },

    renderConfidenceOverlay() {
      const overlayId = "bulk-confidence-overlay"
      let overlay = document.getElementById(overlayId)

      if (!overlay) {
        overlay = document.createElement("div")
        overlay.id = overlayId
        overlay.style.cssText = "position:absolute;right:-20px;top:0;display:flex;flex-direction:column;gap:2px;pointer-events:none;"
        this.el.parentElement.style.position = "relative"
        this.el.parentElement.appendChild(overlay)
      }

      const colorMap = {
        high: "#34d399",    // emerald-400
        medium: "#fbbf24",  // amber-400
        low: "#fb923c",     // orange-400
        error: "#f87171",   // red-400
      }

      const lineHeight = 20 // approximate px per line
      overlay.innerHTML = ""

      Object.entries(this.confidenceIndicators).forEach(([lineIdx, level]) => {
        const dot = document.createElement("div")
        const color = colorMap[level] || "#9ca3af"
        dot.style.cssText = `width:8px;height:8px;border-radius:50%;background:${color};position:absolute;top:${(parseInt(lineIdx)-1) * lineHeight + 6}px;`
        overlay.appendChild(dot)
      })
    },

    clickSelector(selector) {
      const button = document.querySelector(selector)

      if (button && !button.disabled) {
        button.click()
      }
    },

    applyTypeAutocomplete() {
      const completion = computeTypeAutocomplete({
        value: this.el.value,
        start: this.el.selectionStart,
        end: this.el.selectionEnd,
      })

      if (!completion) {
        return false
      }

      this.el.value = completion.nextValue
      this.el.setSelectionRange(completion.cursor, completion.cursor)
      this.el.dispatchEvent(new Event("input", {bubbles: true}))

      return true
    },
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  metadata: {
    keydown: (event) => ({
      key: event.key,
      altKey: event.altKey,
      ctrlKey: event.ctrlKey,
      metaKey: event.metaKey,
      shiftKey: event.shiftKey,
    }),
  },
  hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

const scheduleFlashAutoDismiss = () => {
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

const copyTextUsingExecCommand = (text) => {
  const textarea = document.createElement("textarea")
  textarea.value = text
  textarea.setAttribute("readonly", "")
  textarea.style.position = "fixed"
  textarea.style.opacity = "0"
  textarea.style.pointerEvents = "none"

  document.body.appendChild(textarea)
  textarea.select()
  textarea.setSelectionRange(0, textarea.value.length)

  let copied = false

  try {
    copied = document.execCommand("copy")
  } catch (_) {
    copied = false
  }

  document.body.removeChild(textarea)
  return copied
}

const copyTextToClipboard = async (text) => {
  if (typeof text !== "string" || text.length === 0) {
    return false
  }

  if (navigator?.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch (_) {}
  }

  return copyTextUsingExecCommand(text)
}

window.addEventListener("phx:copy-to-clipboard", async (event) => {
  const text = event?.detail?.text
  const copied = await copyTextToClipboard(text)

  if (!copied) {
    console.warn("Clipboard copy failed for phx:copy-to-clipboard event")
  }
})

scheduleFlashAutoDismiss()

window.addEventListener("phx:page-loading-stop", () => {
  scheduleFlashAutoDismiss()
})

const flashObserver = new MutationObserver(() => {
  scheduleFlashAutoDismiss()
})

flashObserver.observe(document.body, {childList: true, subtree: true})
window.addEventListener("pagehide", () => flashObserver.disconnect(), {once: true})

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}


// Keyboard navigation detection
// Adds .keyboard-nav-active to body when Tab is pressed, removes it on mouse click.
// This enables enhanced focus indicators for keyboard users without affecting mouse users.
document.addEventListener("keydown", (e) => {
  if (e.key === "Tab") {
    document.body.classList.add("keyboard-nav-active")
  }
})

document.addEventListener("mousedown", () => {
  document.body.classList.remove("keyboard-nav-active")
})
