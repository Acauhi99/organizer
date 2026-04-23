import {parsePositiveInteger} from "../features/number_parsers"
import {formatClockFromSeconds} from "../features/timer_clock"
import {
  currentNotificationPermission,
  notificationPermissionMessage,
  playTimerCompletedSound,
} from "../features/notifications"

const MAX_TIMER_MINUTES = 720
const DEFAULT_TIMER_MINUTES = 30
const TIMER_COMPLETED_EVENT = "organizer:notification-permission-updated"

const updateTimerProgressBar = (hook) => {
  if (!(hook.progressBar instanceof HTMLElement)) {
    return
  }

  const elapsed = Math.max(0, hook.durationSeconds - hook.remainingSeconds)
  const ratio = hook.durationSeconds > 0 ? elapsed / hook.durationSeconds : 0
  const width = Math.min(100, Math.max(0, Math.round(ratio * 100)))
  hook.progressBar.style.width = `${width}%`
}

const updateTimerRemainingText = (hook) => {
  if (!(hook.remainingLabel instanceof HTMLElement)) {
    return
  }

  hook.remainingLabel.textContent = `Restante: ${formatClockFromSeconds(hook.remainingSeconds)}`
}

const updateTimerStatusBadge = (hook) => {
  if (!(hook.statusBadge instanceof HTMLElement)) {
    return
  }

  if (hook.completed) {
    hook.statusBadge.textContent = hook.completeLabel
    return
  }

  if (hook.running) {
    hook.statusBadge.textContent = "Em andamento"
    return
  }

  if (hook.remainingSeconds < hook.durationSeconds) {
    hook.statusBadge.textContent = "Pausado"
    return
  }

  hook.statusBadge.textContent = "Pronto"
}

const updateTimerButtons = (hook) => {
  if (hook.startButton instanceof HTMLButtonElement) {
    hook.startButton.disabled = hook.running
  }

  if (hook.pauseButton instanceof HTMLButtonElement) {
    hook.pauseButton.disabled = !hook.running
  }
}

const updateFeedbackByPermission = (hook) => {
  const permission = currentNotificationPermission()

  if (hook.feedbackLabel instanceof HTMLElement) {
    hook.feedbackLabel.textContent = notificationPermissionMessage(permission)
  }
}

const updateTimerUI = (hook) => {
  updateTimerStatusBadge(hook)
  updateTimerRemainingText(hook)
  updateTimerProgressBar(hook)
  updateTimerButtons(hook)
  updateFeedbackByPermission(hook)
}

const clearTimerInterval = (hook) => {
  if (hook.intervalId !== null) {
    window.clearInterval(hook.intervalId)
    hook.intervalId = null
  }
}

const selectedTaskContext = (taskSelect) => {
  const selectedTaskTitle =
    taskSelect instanceof HTMLSelectElement
      ? taskSelect.options[taskSelect.selectedIndex]?.textContent || ""
      : ""

  if (selectedTaskTitle && selectedTaskTitle !== "Selecione uma tarefa em andamento") {
    return `Tarefa: ${selectedTaskTitle}`
  }

  return "Seu período de foco terminou."
}

const notifyTimerCompletion = (hook) => {
  if (currentNotificationPermission() === "granted") {
    try {
      new Notification("Time Box concluído", {
        body: selectedTaskContext(hook.selectTask),
        tag: "organizer-task-timer",
        renotify: true,
      })
    } catch (_) {}
  }

  playTimerCompletedSound()
}

const completeTimer = (hook) => {
  hook.running = false
  hook.completed = true
  hook.remainingSeconds = 0
  clearTimerInterval(hook)
  updateTimerUI(hook)
  notifyTimerCompletion(hook)
}

const startTimer = (hook) => {
  if (hook.running) {
    return
  }

  if (hook.remainingSeconds <= 0) {
    hook.remainingSeconds = hook.durationSeconds
  }

  hook.completed = false
  hook.running = true
  updateTimerUI(hook)

  hook.intervalId = window.setInterval(() => {
    hook.remainingSeconds -= 1

    if (hook.remainingSeconds <= 0) {
      completeTimer(hook)
      return
    }

    updateTimerUI(hook)
  }, 1000)
}

const pauseTimer = (hook) => {
  hook.running = false
  clearTimerInterval(hook)
  updateTimerUI(hook)
}

const resetTimer = (hook) => {
  hook.running = false
  hook.completed = false
  clearTimerInterval(hook)
  hook.remainingSeconds = hook.durationSeconds
  updateTimerUI(hook)
}

const applyDurationFromControls = (hook) => {
  const minutesInputValue =
    hook.minutesInput instanceof HTMLInputElement ? hook.minutesInput.value : null
  const presetValue =
    hook.presetSelect instanceof HTMLSelectElement ? hook.presetSelect.value : null

  const minutes =
    parsePositiveInteger(minutesInputValue) ||
    parsePositiveInteger(presetValue) ||
    hook.defaultMinutes

  hook.durationSeconds = Math.min(MAX_TIMER_MINUTES, minutes) * 60

  if (hook.minutesInput instanceof HTMLInputElement) {
    hook.minutesInput.value = String(Math.floor(hook.durationSeconds / 60))
  }

  resetTimer(hook)
}

const TaskTimerBoxHook = {
  mounted() {
    this.selectTask = this.el.querySelector("#task-timer-task-select")
    this.presetSelect = this.el.querySelector("#task-timer-preset")
    this.minutesInput = this.el.querySelector("#task-timer-minutes")
    this.applyButton = this.el.querySelector("#task-timer-apply")
    this.startButton = this.el.querySelector("#task-timer-start")
    this.pauseButton = this.el.querySelector("#task-timer-pause")
    this.resetButton = this.el.querySelector("#task-timer-reset")
    this.statusBadge = this.el.querySelector("#task-timer-status")
    this.remainingLabel = this.el.querySelector("#task-timer-remaining")
    this.progressBar = this.el.querySelector("#task-timer-progress")
    this.feedbackLabel = this.el.querySelector("#task-timer-feedback")

    this.defaultMinutes = parsePositiveInteger(this.el.dataset.defaultMinutes) || DEFAULT_TIMER_MINUTES
    this.completeLabel = this.el.dataset.completeLabel || "Tempo concluído"
    this.durationSeconds = this.defaultMinutes * 60
    this.remainingSeconds = this.durationSeconds
    this.intervalId = null
    this.running = false
    this.completed = false

    this.updateUI = () => updateTimerUI(this)
    this.clearTimerInterval = () => clearTimerInterval(this)
    this.startTimer = () => startTimer(this)
    this.pauseTimer = () => pauseTimer(this)
    this.resetTimer = () => resetTimer(this)
    this.applyDurationFromControls = () => applyDurationFromControls(this)

    this.onPermissionUpdated = (event) => {
      const permission = event?.detail?.permission

      if (typeof permission === "string" && this.feedbackLabel instanceof HTMLElement) {
        this.feedbackLabel.textContent = notificationPermissionMessage(permission)
        return
      }

      updateFeedbackByPermission(this)
    }

    this.onPresetChanged = () => {
      const minutes =
        this.presetSelect instanceof HTMLSelectElement
          ? parsePositiveInteger(this.presetSelect.value)
          : null

      if (this.minutesInput instanceof HTMLInputElement && minutes !== null) {
        this.minutesInput.value = String(minutes)
      }
    }

    this.onApplyClick = () => this.applyDurationFromControls()
    this.onStartClick = () => this.startTimer()
    this.onPauseClick = () => this.pauseTimer()
    this.onResetClick = () => this.resetTimer()

    if (this.presetSelect instanceof HTMLElement) {
      this.presetSelect.addEventListener("change", this.onPresetChanged)
    }

    if (this.applyButton instanceof HTMLElement) {
      this.applyButton.addEventListener("click", this.onApplyClick)
    }

    if (this.startButton instanceof HTMLElement) {
      this.startButton.addEventListener("click", this.onStartClick)
    }

    if (this.pauseButton instanceof HTMLElement) {
      this.pauseButton.addEventListener("click", this.onPauseClick)
    }

    if (this.resetButton instanceof HTMLElement) {
      this.resetButton.addEventListener("click", this.onResetClick)
    }

    window.addEventListener(TIMER_COMPLETED_EVENT, this.onPermissionUpdated)
    this.updateUI()
  },

  destroyed() {
    this.clearTimerInterval?.()

    if (this.presetSelect instanceof HTMLElement) {
      this.presetSelect.removeEventListener("change", this.onPresetChanged)
    }

    if (this.applyButton instanceof HTMLElement) {
      this.applyButton.removeEventListener("click", this.onApplyClick)
    }

    if (this.startButton instanceof HTMLElement) {
      this.startButton.removeEventListener("click", this.onStartClick)
    }

    if (this.pauseButton instanceof HTMLElement) {
      this.pauseButton.removeEventListener("click", this.onPauseClick)
    }

    if (this.resetButton instanceof HTMLElement) {
      this.resetButton.removeEventListener("click", this.onResetClick)
    }

    window.removeEventListener(TIMER_COMPLETED_EVENT, this.onPermissionUpdated)
  },
}

export default TaskTimerBoxHook
