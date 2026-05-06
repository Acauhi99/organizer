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

const NOOP = () => {}

const readCsrfToken = () => {
  const element = document.querySelector("meta[name='csrf-token']")
  return element?.getAttribute("content") || ""
}

const mergeHooks = () => ({
  ...colocatedHooks,
  ...organizerHooks,
})

const buildLiveSocket = ({csrfToken, hooks}) =>
  new LiveSocket("/live", Socket, {
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

const registerTopbarBindings = ({target = window} = {}) => {
  topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})

  const onStart = () => topbar.show(300)
  const onStop = () => topbar.hide()

  target.addEventListener("phx:page-loading-start", onStart)
  target.addEventListener("phx:page-loading-stop", onStop)

  return () => {
    target.removeEventListener("phx:page-loading-start", onStart)
    target.removeEventListener("phx:page-loading-stop", onStop)
  }
}

const registerGlobalFeatures = () => [
  registerScrollToElementListener(),
  registerCopyToClipboardListener(),
  initializeFlashAutoDismiss(),
  registerKeyboardNavigationIndicators(),
]

const registerDevLiveReload = ({target = window} = {}) => {
  if (process.env.NODE_ENV !== "development") {
    return NOOP
  }

  let keyDown = null
  let reloader = null
  let detachClickHandler = NOOP

  const onKeyDown = (event) => {
    keyDown = event.key
  }

  const onKeyUp = () => {
    keyDown = null
  }

  const bindClickShortcutHandler = () => {
    detachClickHandler()

    const onClick = (event) => {
      if (keyDown !== "c" && keyDown !== "d") {
        return
      }

      event.preventDefault()
      event.stopImmediatePropagation()

      if (keyDown === "c") {
        reloader?.openEditorAtCaller(event.target)
      } else {
        reloader?.openEditorAtDef(event.target)
      }
    }

    target.addEventListener("click", onClick, true)
    detachClickHandler = () => target.removeEventListener("click", onClick, true)
  }

  const onAttached = ({detail}) => {
    reloader = detail
    reloader.enableServerLogs()
    bindClickShortcutHandler()
    window.liveReloader = reloader
  }

  target.addEventListener("phx:live_reload:attached", onAttached)
  target.addEventListener("keydown", onKeyDown)
  target.addEventListener("keyup", onKeyUp)

  return () => {
    target.removeEventListener("phx:live_reload:attached", onAttached)
    target.removeEventListener("keydown", onKeyDown)
    target.removeEventListener("keyup", onKeyUp)
    detachClickHandler()
  }
}

const runCleanups = (cleanups) => {
  cleanups.forEach((cleanup) => {
    cleanup()
  })
}

const bootstrap = () => {
  const hooks = mergeHooks()
  const liveSocket = buildLiveSocket({csrfToken: readCsrfToken(), hooks})

  const cleanups = [
    registerTopbarBindings(),
    ...registerGlobalFeatures(),
    registerDevLiveReload(),
  ]

  liveSocket.connect()
  window.liveSocket = liveSocket

  return {
    liveSocket,
    destroy: () => runCleanups(cleanups),
  }
}

window.organizerApp = bootstrap()
