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
    value: (today) => `financeiro: tipo=despesa | valor=0 | categoria=geral | data=${today}`,
  },
  {
    prefixes: ["r", "rec", "receita", "income"],
    value: (today) => `financeiro: tipo=receita | valor=0 | categoria=geral | data=${today}`,
  },
  {
    prefixes: ["d", "des", "despesa", "expense"],
    value: (today) => `financeiro: tipo=despesa | valor=0 | categoria=geral | data=${today}`,
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
  BulkCaptureEditor: {
    mounted() {
      this.previewSelector = this.el.dataset.previewSelector || BULK_DEFAULT_SELECTORS.preview
      this.importSelector = this.el.dataset.importSelector || BULK_DEFAULT_SELECTORS.import
      this.fixAllSelector = this.el.dataset.fixAllSelector || BULK_DEFAULT_SELECTORS.fixAll

      this.onKeyDown = (event) => {
        const action = resolveBulkShortcutAction(event)

        if (!action) {
          return
        }

        if (action === "autocomplete") {
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

      this.el.addEventListener("keydown", this.onKeyDown)
    },

    destroyed() {
      this.el.removeEventListener("keydown", this.onKeyDown)
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

window.addEventListener("phx:form:reset", (event) => {
  const formId = event?.detail?.id

  if (!formId) {
    return
  }

  const form = document.getElementById(formId)

  if (!form) {
    return
  }

  form.reset()
})

scheduleFlashAutoDismiss()

window.addEventListener("phx:page-loading-stop", () => {
  scheduleFlashAutoDismiss()
})

const flashObserver = new MutationObserver(() => {
  scheduleFlashAutoDismiss()
})

flashObserver.observe(document.body, {childList: true, subtree: true})

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

