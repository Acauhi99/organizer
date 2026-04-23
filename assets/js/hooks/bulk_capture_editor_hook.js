import {
  BULK_DEFAULT_SELECTORS,
  computeFieldAutocomplete,
  computeTypeAutocomplete,
  resolveBulkShortcutAction,
} from "../features/bulk_capture"

const OVERLAY_ID = "bulk-confidence-overlay"
const OVERLAY_STYLE = "position:absolute;right:-20px;top:0;display:flex;flex-direction:column;gap:2px;pointer-events:none;"
const LINE_HEIGHT_PX = 20
const LINE_OFFSET_PX = 6

const CONFIDENCE_COLORS = {
  high: "#34d399",
  medium: "#fbbf24",
  low: "#fb923c",
  error: "#f87171",
}

const selectorByAction = (hook) => ({
  preview: hook.previewSelector,
  fixAll: hook.fixAllSelector,
  import: hook.importSelector,
})

const updateConfidenceIndicator = (hook, payload) => {
  const {index, confidence_level: confidenceLevel} = payload

  if (confidenceLevel === "ignored") {
    delete hook.confidenceIndicators[index]
  } else {
    hook.confidenceIndicators[index] = confidenceLevel
  }

  hook.renderConfidenceOverlay()
}

const applyFieldAutocompleteResult = (hook, context, completed) => {
  const ctx = context

  if (!ctx || !completed) {
    return
  }

  const source = hook.el.value
  const prefixStart = ctx.lineStart + ctx.beforeCursor.length - ctx.prefix.length
  const nextValue = source.slice(0, prefixStart) + completed + source.slice(prefixStart + ctx.prefix.length)

  hook.el.value = nextValue
  const newCursor = prefixStart + completed.length
  hook.el.setSelectionRange(newCursor, newCursor)
  hook.el.dispatchEvent(new Event("input", {bubbles: true}))
}

const applyTypeAutocomplete = (hook) => {
  const completion = computeTypeAutocomplete({
    value: hook.el.value,
    start: hook.el.selectionStart,
    end: hook.el.selectionEnd,
  })

  if (!completion) {
    return false
  }

  hook.el.value = completion.nextValue
  hook.el.setSelectionRange(completion.cursor, completion.cursor)
  hook.el.dispatchEvent(new Event("input", {bubbles: true}))

  return true
}

const clickSelector = (selector) => {
  const button = document.querySelector(selector)

  if (button && !button.disabled) {
    button.click()
  }
}

const removeConfidenceOverlay = () => {
  const overlay = document.getElementById(OVERLAY_ID)

  if (overlay) {
    overlay.remove()
  }
}

const ensureConfidenceOverlay = (hook) => {
  let overlay = document.getElementById(OVERLAY_ID)

  if (!overlay) {
    overlay = document.createElement("div")
    overlay.id = OVERLAY_ID
    overlay.style.cssText = OVERLAY_STYLE

    if (hook.el.parentElement) {
      hook.el.parentElement.style.position = "relative"
      hook.el.parentElement.appendChild(overlay)
    }
  }

  return overlay
}

const renderConfidenceOverlay = (hook) => {
  const overlay = ensureConfidenceOverlay(hook)

  if (!overlay) {
    return
  }

  overlay.innerHTML = ""

  Object.entries(hook.confidenceIndicators).forEach(([lineIndex, level]) => {
    const dot = document.createElement("div")
    const color = CONFIDENCE_COLORS[level] || "#9ca3af"
    const top = (Number.parseInt(lineIndex, 10) - 1) * LINE_HEIGHT_PX + LINE_OFFSET_PX

    dot.style.cssText =
      `width:8px;height:8px;border-radius:50%;background:${color};position:absolute;top:${top}px;`

    overlay.appendChild(dot)
  })
}

const validateCurrentLines = (hook) => {
  const lines = hook.el.value.split(/\r?\n/)

  if (!hook._lastValidatedLines) {
    hook._lastValidatedLines = []
  }

  lines.forEach((line, index) => {
    const previousLine = hook._lastValidatedLines[index] || ""

    if (line === previousLine) {
      return
    }

    if (line.trim().length > 0) {
      hook.pushEvent("validate_bulk_line", {
        line,
        index: index + 1,
      })
        .then((reply) => {
          if (reply) {
            hook.handleBulkLineValidated(reply)
          }
        })
        .catch(() => {})

      return
    }

    hook.handleBulkLineValidated({
      index: index + 1,
      confidence_level: "ignored",
    })
  })

  hook._lastValidatedLines = lines.slice()
}

const BulkCaptureEditorHook = {
  mounted() {
    this.previewSelector = this.el.dataset.previewSelector || BULK_DEFAULT_SELECTORS.preview
    this.importSelector = this.el.dataset.importSelector || BULK_DEFAULT_SELECTORS.import
    this.fixAllSelector = this.el.dataset.fixAllSelector || BULK_DEFAULT_SELECTORS.fixAll

    this.validationTimeout = null
    this.previousValue = ""
    this.confidenceIndicators = {}

    this.applyFieldAutocompleteResult = (context, completed) => {
      applyFieldAutocompleteResult(this, context, completed)
    }

    this.applyTypeAutocomplete = () => applyTypeAutocomplete(this)

    this.clickSelector = (selector) => {
      clickSelector(selector)
    }

    this.validateCurrentLines = () => {
      validateCurrentLines(this)
    }

    this.renderConfidenceOverlay = () => {
      renderConfidenceOverlay(this)
    }

    this.handleBulkLineValidated = (payload) => {
      updateConfidenceIndicator(this, payload)
    }

    this.onKeyDown = (event) => {
      const action = resolveBulkShortcutAction(event)

      if (!action) {
        return
      }

      if (action === "autocomplete") {
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

        if (this.applyTypeAutocomplete()) {
          event.preventDefault()
        }

        return
      }

      event.preventDefault()
      this.clickSelector(selectorByAction(this)[action])
    }

    this.onInput = (event) => {
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
  },

  destroyed() {
    clearTimeout(this.validationTimeout)
    this.el.removeEventListener("keydown", this.onKeyDown)
    this.el.removeEventListener("input", this.onInput)
    removeConfidenceOverlay()
  },
}

export default BulkCaptureEditorHook
