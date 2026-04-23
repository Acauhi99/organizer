export const parsePositiveTimeoutMs = (value) => {
  const timeoutMs = Number(value)

  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    return null
  }

  return timeoutMs
}

export const parsePositiveInteger = (value) => {
  const parsed = Number.parseInt(value, 10)

  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null
  }

  return parsed
}
