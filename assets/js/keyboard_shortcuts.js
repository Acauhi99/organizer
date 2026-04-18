/**
 * KeyboardShortcuts hook
 *
 * Listens for keyboard shortcuts and pushes events to LiveView.
 *
 * Shortcuts:
 *   Alt+B  — Focus the bulk import textarea
 *   Alt+O  — Toggle operations panel
 *   Alt+A  — Toggle analytics panel
 *   Alt+F  — Toggle focus mode
 *   Esc    — Exit focus mode (only when focus mode is active)
 *   ?      — Show keyboard shortcuts help (only when not in an input/textarea)
 */

const INPUT_TAGS = new Set(["INPUT", "TEXTAREA", "SELECT"])

const isTypingInInput = (target) => INPUT_TAGS.has(target.tagName) || target.isContentEditable

const KeyboardShortcuts = {
  mounted() {
    this.onKeyDown = (event) => {
      // Alt+B — focus bulk import textarea
      if (event.altKey && !event.ctrlKey && !event.metaKey && event.key === "b") {
        event.preventDefault()
        const textarea = document.getElementById("bulk-payload-input")
        if (textarea) {
          textarea.focus()
          textarea.scrollIntoView({behavior: "smooth", block: "center"})
        }
        return
      }

      // Alt+O — toggle operations panel
      if (event.altKey && !event.ctrlKey && !event.metaKey && event.key === "o") {
        event.preventDefault()
        this.pushEvent("toggle_operations_panel", {})
        return
      }

      // Alt+A — toggle analytics panel
      if (event.altKey && !event.ctrlKey && !event.metaKey && event.key === "a") {
        event.preventDefault()
        this.pushEvent("toggle_analytics_panel", {})
        return
      }

      // Alt+F — toggle focus mode
      if (event.altKey && !event.ctrlKey && !event.metaKey && event.key === "f") {
        event.preventDefault()
        this.pushEvent("toggle_focus_mode", {})
        return
      }

      // Esc — exit focus mode (only when focus mode is active)
      if (event.key === "Escape" && this.el.dataset.focusMode === "true") {
        event.preventDefault()
        this.pushEvent("exit_focus_mode", {})
        return
      }

      // ? — show keyboard shortcuts help (only when not typing in an input)
      if (event.key === "?" && !isTypingInInput(event.target)) {
        event.preventDefault()
        this.pushEvent("show_keyboard_shortcuts", {})
        return
      }
    }

    document.addEventListener("keydown", this.onKeyDown)
  },

  destroyed() {
    document.removeEventListener("keydown", this.onKeyDown)
  },
}

export default KeyboardShortcuts
