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

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const hooks = {
  ...colocatedHooks,
  BulkCaptureEditor: {
    mounted() {
      this.previewSelector = this.el.dataset.previewSelector || "#bulk-preview-btn"
      this.importSelector = this.el.dataset.importSelector || "#bulk-import-btn"
      this.fixAllSelector = this.el.dataset.fixAllSelector || "#bulk-fix-all-btn"

      this.onKeyDown = (event) => {
        const isPrimaryModifier = event.ctrlKey || event.metaKey

        if (isPrimaryModifier && !event.shiftKey && event.key === "Enter") {
          event.preventDefault()
          this.clickSelector(this.previewSelector)
          return
        }

        if (isPrimaryModifier && event.shiftKey && event.key.toLowerCase() === "f") {
          event.preventDefault()
          this.clickSelector(this.fixAllSelector)
          return
        }

        if (isPrimaryModifier && event.shiftKey && event.key.toLowerCase() === "i") {
          event.preventDefault()
          this.clickSelector(this.importSelector)
          return
        }

        if (event.key === "Tab" && !event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey) {
          if (this.applyTypeAutocomplete()) {
            event.preventDefault()
          }
        }
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
      const start = this.el.selectionStart
      const end = this.el.selectionEnd

      if (typeof start !== "number" || typeof end !== "number" || start !== end) {
        return false
      }

      const value = this.el.value || ""
      const lineStart = value.lastIndexOf("\n", start - 1) + 1
      const lineEndIndex = value.indexOf("\n", start)
      const lineEnd = lineEndIndex === -1 ? value.length : lineEndIndex
      const currentLine = value.slice(lineStart, lineEnd)
      const trimmed = currentLine.trim().toLowerCase()

      if (trimmed === "" || currentLine.includes(":")) {
        return false
      }

      const today = new Date().toISOString().slice(0, 10)

      const templateByPrefix = [
        {prefixes: ["t", "ta", "tar", "task", "tarefa"], value: "tarefa: "},
        {
          prefixes: ["f", "fi", "fin", "finance", "financeiro"],
          value: `financeiro: tipo=despesa | valor=0 | categoria=geral | data=${today}`,
        },
        {
          prefixes: ["r", "rec", "receita", "income"],
          value: `financeiro: tipo=receita | valor=0 | categoria=geral | data=${today}`,
        },
        {
          prefixes: ["d", "des", "despesa", "expense"],
          value: `financeiro: tipo=despesa | valor=0 | categoria=geral | data=${today}`,
        },
        {prefixes: ["m", "me", "meta", "goal"], value: "meta: "},
      ]

      const match = templateByPrefix.find((entry) =>
        entry.prefixes.some((prefix) => trimmed === prefix || trimmed.startsWith(prefix))
      )

      if (!match) {
        return false
      }

      const nextValue = `${value.slice(0, lineStart)}${match.value}${value.slice(lineEnd)}`
      this.el.value = nextValue

      const cursor = lineStart + match.value.length
      this.el.setSelectionRange(cursor, cursor)
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

    const timeoutMs = Number(flashEl.dataset.autoDismissMs)

    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
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

