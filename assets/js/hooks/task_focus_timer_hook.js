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

const taskFocusValue = (payload, camelKey) => {
  if (!payload || typeof payload !== "object") {
    return undefined
  }

  const snakeKey = camelKey.replace(/[A-Z]/g, (segment) => `_${segment.toLowerCase()}`)

  if (Object.prototype.hasOwnProperty.call(payload, camelKey)) {
    return payload[camelKey]
  }

  if (Object.prototype.hasOwnProperty.call(payload, snakeKey)) {
    return payload[snakeKey]
  }

  return undefined
}

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

  const durationMinutes = normalizeTaskFocusMinutes(
    taskFocusValue(payload, "durationMinutes"),
    TASK_FOCUS_DEFAULT_MINUTES
  )
  const totalSeconds = taskFocusTotalSeconds(durationMinutes)
  const statuses = ["idle", "running", "paused", "finished"]
  const statusValue = taskFocusValue(payload, "status")
  const status = statuses.includes(statusValue) ? statusValue : TASK_FOCUS_DEFAULT_STATUS
  const remainingRaw = Number(taskFocusValue(payload, "remainingSeconds"))
  const remainingSeconds = Number.isFinite(remainingRaw)
    ? clamp(Math.floor(remainingRaw), 0, totalSeconds)
    : totalSeconds

  const taskIdValue = taskFocusValue(payload, "taskId")
  const taskLabelValue = taskFocusValue(payload, "taskLabel")
  const endsAtMsValue = Number(taskFocusValue(payload, "endsAtMs"))
  const notifiedValue = taskFocusValue(payload, "notified")

  const taskId = typeof taskIdValue === "string" ? taskIdValue : ""
  const taskLabel = typeof taskLabelValue === "string" ? taskLabelValue : ""

  let normalized = {
    taskId,
    taskLabel,
    durationMinutes,
    remainingSeconds,
    status,
    endsAtMs: Number.isFinite(endsAtMsValue) ? Math.floor(endsAtMsValue) : null,
    notified: notifiedValue === true || notifiedValue === "true",
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

const TaskFocusTimerHook = {
  mounted() {
    this.storageKey = this.el.dataset.storageKey || "organizer:task-focus-timer"
    this.intervalId = null
    this.startWithoutTask = false
    this.pendingSyncedTask = null
    this.lastPushedStateHash = null
    this.handleNotificationPermissionUpdated = () => this.render()

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
    this.handleEvent("task_focus_state_sync", (payload) => this.syncStateFromServer(payload))
    window.addEventListener(
      "organizer:notification-permission-updated",
      this.handleNotificationPermissionUpdated
    )

    this.state = this.loadState()
    this.lastPushedStateHash = JSON.stringify(this.serverPayload())
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
    window.removeEventListener(
      "organizer:notification-permission-updated",
      this.handleNotificationPermissionUpdated
    )
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
    const serverState = this.loadInitialStateFromServer()

    if (serverState) {
      return serverState
    }

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

  loadInitialStateFromServer() {
    try {
      const rawState = this.el.dataset.initialState

      if (!rawState) {
        return null
      }

      const parsed = JSON.parse(rawState)

      if (!parsed || typeof parsed !== "object") {
        return null
      }

      return normalizeTaskFocusState(parsed)
    } catch (_) {
      return null
    }
  },

  persistState(pushServer = true) {
    try {
      window.localStorage.setItem(this.storageKey, JSON.stringify(this.state))
    } catch (_) {}

    if (pushServer) {
      this.pushStateToServer()
    }
  },

  serverPayload() {
    const totalSeconds = this.totalSeconds()

    return {
      taskId: this.state.taskId,
      taskLabel: this.state.taskLabel,
      durationMinutes: this.state.durationMinutes,
      remainingSeconds: clamp(this.state.remainingSeconds, 0, totalSeconds),
      status: this.state.status,
      endsAtMs: Number.isFinite(this.state.endsAtMs) ? Math.floor(this.state.endsAtMs) : null,
      notified: this.state.notified === true,
    }
  },

  pushStateToServer() {
    const payload = this.serverPayload()
    const nextHash = JSON.stringify(payload)

    if (nextHash === this.lastPushedStateHash) {
      return
    }

    this.lastPushedStateHash = nextHash
    this.pushEvent("task_focus_state_changed", payload)
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

  syncStateFromServer(payload) {
    this.state = normalizeTaskFocusState(payload)
    this.startWithoutTask = false
    this.lastPushedStateHash = JSON.stringify(this.serverPayload())

    this.syncSelectorsFromState()
    this.applyPendingSyncedTask()
    this.ensureTickerState()
    this.persistState(false)
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
      this.state.notified = true
      this.notifyCompletion()
    }

    this.persistState()
    this.render()
  },

  notifyCompletion() {
    if (!browserSupportsNotifications() || Notification.permission !== "granted") {
      return
    }

    try {
      const taskLabel = this.state.taskLabel || "sua tarefa"
      const notification = new Notification("Time box concluído", {
        body: `O tempo para ${taskLabel} terminou.`,
        tag: `task-focus:${this.state.taskId || "general"}`,
      })

      window.setTimeout(() => {
        notification.close?.()
      }, 10_000)
    } catch (_) {}
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
}

export default TaskFocusTimerHook
