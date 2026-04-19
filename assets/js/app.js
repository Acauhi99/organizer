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

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const hooks = {
  ...colocatedHooks,
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
