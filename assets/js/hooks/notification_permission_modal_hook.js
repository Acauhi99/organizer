import {
  browserNotificationsSupported,
  currentNotificationPermission,
} from "../features/notifications"
import {parsePositiveInteger} from "../features/number_parsers"

const NOTIFICATION_STORAGE_KEY = "organizer:notification_prompt_next_at"

const updateStatusText = (statusLabel, permission) => {
  if (!(statusLabel instanceof HTMLElement)) {
    return
  }

  if (permission === "granted") {
    statusLabel.textContent = "Notificações liberadas. Você será avisado no fim do timer."
    return
  }

  if (permission === "denied") {
    statusLabel.textContent =
      "As notificações foram bloqueadas. Você pode reativar nas configurações do navegador."
    return
  }

  statusLabel.textContent =
    'Clique em "Ativar notificações" para permitir alertas no navegador.'
}

const broadcastPermissionUpdate = (permission) => {
  window.dispatchEvent(
    new CustomEvent("organizer:notification-permission-updated", {
      detail: {permission},
    })
  )
}

const scheduleNextPrompt = ({storageKey, promptDays}) => {
  const nextAt = Date.now() + promptDays * 24 * 60 * 60 * 1000
  localStorage.setItem(storageKey, String(nextAt))
}

const canPromptNow = (storageKey) => {
  const nextAtRaw = localStorage.getItem(storageKey)
  const nextAt = Number.parseInt(nextAtRaw || "", 10)

  return !Number.isFinite(nextAt) || Date.now() >= nextAt
}

const shouldShowPrompt = (state) => {
  const permission = currentNotificationPermission()
  updateStatusText(state.statusLabel, permission)

  if (permission !== "default") {
    broadcastPermissionUpdate(permission)
    return false
  }

  return canPromptNow(state.storageKey)
}

const showModal = (element) => {
  element.classList.remove("hidden")
  element.classList.add("flex")
  element.setAttribute("aria-hidden", "false")
}

const hideModal = (element) => {
  element.classList.add("hidden")
  element.classList.remove("flex")
  element.setAttribute("aria-hidden", "true")
}

const createState = (hook) => ({
  element: hook.el,
  allowButton: hook.el.querySelector("#notification-permission-allow"),
  laterButton: hook.el.querySelector("#notification-permission-later"),
  statusLabel: hook.el.querySelector("#notification-permission-status"),
  storageKey: NOTIFICATION_STORAGE_KEY,
  promptDays: parsePositiveInteger(hook.el.dataset.remindAfterDays) || 7,
  cleanup: [],
})

const addListener = (target, event, listener, cleanup) => {
  if (!(target instanceof HTMLElement)) {
    return
  }

  target.addEventListener(event, listener)
  cleanup.push(() => target.removeEventListener(event, listener))
}

const createAllowHandler = (state) => async () => {
  if (!browserNotificationsSupported()) {
    hideModal(state.element)
    return
  }

  try {
    const permission = await Notification.requestPermission()
    updateStatusText(state.statusLabel, permission)
    broadcastPermissionUpdate(permission)

    if (permission === "granted") {
      localStorage.removeItem(state.storageKey)
    } else {
      scheduleNextPrompt(state)
    }
  } catch (_) {
    scheduleNextPrompt(state)
  }

  hideModal(state.element)
}

const createLaterHandler = (state) => () => {
  scheduleNextPrompt(state)
  updateStatusText(state.statusLabel, "default")
  broadcastPermissionUpdate("default")
  hideModal(state.element)
}

const wirePermissionActions = (state) => {
  addListener(state.allowButton, "click", createAllowHandler(state), state.cleanup)
  addListener(state.laterButton, "click", createLaterHandler(state), state.cleanup)
}

const openPromptWhenNeeded = (state) => {
  if (shouldShowPrompt(state)) {
    window.setTimeout(() => showModal(state.element), 180)
    return
  }

  hideModal(state.element)
}

const disposeState = (state) => {
  state.cleanup.forEach((cleanup) => cleanup())
  state.cleanup = []
}

const NotificationPermissionModalHook = {
  mounted() {
    this.state = createState(this)
    wirePermissionActions(this.state)
    openPromptWhenNeeded(this.state)
  },

  destroyed() {
    if (!this.state) {
      return
    }

    disposeState(this.state)
    this.state = null
  },
}

export default NotificationPermissionModalHook
