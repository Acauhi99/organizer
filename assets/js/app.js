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

import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/organizer"
import topbar from "../vendor/topbar"
import {initializeFlashAutoDismiss} from "./features/flash_auto_dismiss"
import {registerKeyboardNavigationIndicators} from "./features/keyboard_navigation"
import {registerCopyToClipboardListener} from "./features/clipboard"
import {registerScrollToElementListener} from "./features/scroll_focus"
import {organizerHooks} from "./hooks"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const hooks = {
  ...colocatedHooks,
  ...organizerHooks,
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

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

liveSocket.connect()

registerScrollToElementListener()
registerCopyToClipboardListener()
initializeFlashAutoDismiss()
registerKeyboardNavigationIndicators()

window.liveSocket = liveSocket

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()

    let keyDown

    window.addEventListener("keydown", (event) => {
      keyDown = event.key
    })

    window.addEventListener("keyup", () => {
      keyDown = null
    })

    window.addEventListener("click", (event) => {
      if (keyDown === "c") {
        event.preventDefault()
        event.stopImmediatePropagation()
        reloader.openEditorAtCaller(event.target)
      } else if (keyDown === "d") {
        event.preventDefault()
        event.stopImmediatePropagation()
        reloader.openEditorAtDef(event.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
