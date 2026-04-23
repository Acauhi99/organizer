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

const shouldShowPrompt = (hook) => {
  const permission = currentNotificationPermission()
  updateStatusText(hook.statusLabel, permission)

  if (permission !== "default") {
    broadcastPermissionUpdate(permission)
    return false
  }

  return canPromptNow(hook.storageKey)
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

const NotificationPermissionModalHook = {
  mounted() {
    this.allowButton = this.el.querySelector("#notification-permission-allow")
    this.laterButton = this.el.querySelector("#notification-permission-later")
    this.statusLabel = this.el.querySelector("#notification-permission-status")
    this.storageKey = NOTIFICATION_STORAGE_KEY
    this.promptDays = parsePositiveInteger(this.el.dataset.remindAfterDays) || 7

    this.open = () => {
      showModal(this.el)
    }

    this.close = () => {
      hideModal(this.el)
    }

    this.onAllowClick = async () => {
      if (!browserNotificationsSupported()) {
        this.close()
        return
      }

      try {
        const permission = await Notification.requestPermission()
        updateStatusText(this.statusLabel, permission)
        broadcastPermissionUpdate(permission)

        if (permission === "granted") {
          localStorage.removeItem(this.storageKey)
        } else {
          scheduleNextPrompt(this)
        }
      } catch (_) {
        scheduleNextPrompt(this)
      }

      this.close()
    }

    this.onLaterClick = () => {
      scheduleNextPrompt(this)
      updateStatusText(this.statusLabel, "default")
      broadcastPermissionUpdate("default")
      this.close()
    }

    if (this.allowButton instanceof HTMLElement) {
      this.allowButton.addEventListener("click", this.onAllowClick)
    }

    if (this.laterButton instanceof HTMLElement) {
      this.laterButton.addEventListener("click", this.onLaterClick)
    }

    if (shouldShowPrompt(this)) {
      window.setTimeout(() => this.open(), 180)
    } else {
      this.close()
    }
  },

  destroyed() {
    if (this.allowButton instanceof HTMLElement) {
      this.allowButton.removeEventListener("click", this.onAllowClick)
    }

    if (this.laterButton instanceof HTMLElement) {
      this.laterButton.removeEventListener("click", this.onLaterClick)
    }
  },
}

export default NotificationPermissionModalHook
