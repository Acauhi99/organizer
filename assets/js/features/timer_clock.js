export const formatClockFromSeconds = (seconds) => {
  const safeValue = Math.max(0, Number.isFinite(seconds) ? Math.floor(seconds) : 0)
  const minutes = Math.floor(safeValue / 60)
  const remainingSeconds = safeValue % 60

  return `${String(minutes).padStart(2, "0")}:${String(remainingSeconds).padStart(2, "0")}`
}
