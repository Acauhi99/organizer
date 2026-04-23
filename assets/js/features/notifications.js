export const browserNotificationsSupported = () =>
  typeof window !== "undefined" && "Notification" in window

export const currentNotificationPermission = () => {
  if (!browserNotificationsSupported()) {
    return "unsupported"
  }

  return Notification.permission
}

export const notificationPermissionMessage = (permission) => {
  if (permission === "granted") {
    return "Notificações ativas para alertar no término do timer."
  }

  if (permission === "denied") {
    return "Notificações bloqueadas no navegador. Reative nas configurações do site."
  }

  return "Ative as notificações para ser avisado quando o timer terminar."
}

export const playTimerCompletedSound = () => {
  const AudioCtx = window.AudioContext || window.webkitAudioContext

  if (typeof AudioCtx !== "function") {
    return
  }

  try {
    const context = new AudioCtx()
    const oscillator = context.createOscillator()
    const gain = context.createGain()

    oscillator.type = "triangle"
    oscillator.frequency.setValueAtTime(880, context.currentTime)
    oscillator.connect(gain)
    gain.connect(context.destination)

    gain.gain.setValueAtTime(0.001, context.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.12, context.currentTime + 0.01)
    gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.35)

    oscillator.start(context.currentTime)
    oscillator.stop(context.currentTime + 0.35)

    oscillator.onended = () => {
      context.close().catch(() => {})
    }
  } catch (_) {}
}
