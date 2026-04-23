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
    } catch (_) {}
  }

  return copyTextUsingExecCommand(text)
}

export const registerCopyToClipboardListener = () => {
  window.addEventListener("phx:copy-to-clipboard", async (event) => {
    const text = event?.detail?.text
    const copied = await copyTextToClipboard(text)

    if (!copied) {
      console.warn("Clipboard copy failed for phx:copy-to-clipboard event")
    }
  })
}
