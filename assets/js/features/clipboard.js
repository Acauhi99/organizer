const PHX_COPY_EVENT = "phx:copy-to-clipboard"

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

export const copyTextToClipboard = async (text) => {
  if (typeof text !== "string" || text.length === 0) {
    return false
  }

  if (navigator?.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch (_) {
      // Fallback below.
    }
  }

  return copyTextUsingExecCommand(text)
}

const createClipboardEventListener = ({onFailure}) => async (event) => {
  const text = event?.detail?.text
  const copied = await copyTextToClipboard(text)

  if (!copied) {
    onFailure("Clipboard copy failed for phx:copy-to-clipboard event")
  }
}

export const registerCopyToClipboardListener = ({target = window, onFailure = console.warn} = {}) => {
  const listener = createClipboardEventListener({onFailure})
  target.addEventListener(PHX_COPY_EVENT, listener)

  return () => {
    target.removeEventListener(PHX_COPY_EVENT, listener)
  }
}
