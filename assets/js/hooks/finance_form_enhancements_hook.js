const MONEY_SELECTOR = "input[data-money-mask='true']"
const DATE_SELECTOR = "input[data-date-picker]"
let datePickerControlSequence = 0

const digitsOnly = (value) => `${value || ""}`.replace(/\D+/g, "")

const formatCentsToPtBr = (cents) => {
  const nonNegative = Math.max(cents, 0)
  const integerPart = Math.floor(nonNegative / 100).toString()
  const decimalPart = `${nonNegative % 100}`.padStart(2, "0")
  return `${integerPart},${decimalPart}`
}

const syncMoneyHiddenTarget = (input, centsDigits) => {
  const targetId = input.dataset.moneyHiddenTarget

  if (typeof targetId !== "string" || targetId.trim() === "") {
    return
  }

  const hiddenInput = document.getElementById(targetId)

  if (!(hiddenInput instanceof HTMLInputElement)) {
    return
  }

  hiddenInput.value = centsDigits === "" ? "" : String(Number.parseInt(centsDigits, 10))
}

const maskMoneyInputValue = (value) => {
  const digits = digitsOnly(value)

  if (digits === "") {
    return ""
  }

  const cents = Number.parseInt(digits, 10)

  if (!Number.isFinite(cents)) {
    return ""
  }

  return formatCentsToPtBr(cents)
}

const parsePtBrDateToIso = (value) => {
  const cleaned = `${value || ""}`.trim()
  const match = cleaned.match(/^(\d{2})\/(\d{2})\/(\d{4})$/)

  if (!match) {
    return ""
  }

  const [, day, month, year] = match
  return `${year}-${month}-${day}`
}

const parsePtBrMonthToIso = (value) => {
  const cleaned = `${value || ""}`.trim()
  const match = cleaned.match(/^(\d{2})\/(\d{4})$/)

  if (!match) {
    return ""
  }

  const [, month, year] = match
  return `${year}-${month}`
}

const isoDateToPtBr = (value) => {
  const cleaned = `${value || ""}`.trim()
  const match = cleaned.match(/^(\d{4})-(\d{2})-(\d{2})$/)

  if (!match) {
    return ""
  }

  const [, year, month, day] = match
  return `${day}/${month}/${year}`
}

const isoMonthToPtBr = (value) => {
  const cleaned = `${value || ""}`.trim()
  const match = cleaned.match(/^(\d{4})-(\d{2})$/)

  if (!match) {
    return ""
  }

  const [, year, month] = match
  return `${month}/${year}`
}

const maskDateInputValue = (value) => {
  const digits = digitsOnly(value).slice(0, 8)

  if (digits.length <= 2) {
    return digits
  }

  if (digits.length <= 4) {
    return `${digits.slice(0, 2)}/${digits.slice(2)}`
  }

  return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4)}`
}

const maskMonthInputValue = (value) => {
  const digits = digitsOnly(value).slice(0, 6)

  if (digits.length <= 2) {
    return digits
  }

  return `${digits.slice(0, 2)}/${digits.slice(2)}`
}

const dispatchInputEvent = (element) => {
  element.dispatchEvent(new Event("input", {bubbles: true}))
}

const setInputValueAndNotify = (input, value) => {
  input.value = value
  dispatchInputEvent(input)
}

const enhanceMoneyInput = (input, hook) => {
  if (!(input instanceof HTMLInputElement) || input.dataset.moneyMaskBound === "true") {
    return
  }

  const handleInput = () => {
    const centsDigits = digitsOnly(input.value)
    const masked = maskMoneyInputValue(input.value)

    if (input.value !== masked) {
      input.value = masked
    }

    syncMoneyHiddenTarget(input, centsDigits)
  }

  input.addEventListener("input", handleInput)
  handleInput()

  input.dataset.moneyMaskBound = "true"
  hook.cleanups.push(() => {
    input.removeEventListener("input", handleInput)
    delete input.dataset.moneyMaskBound
  })
}

const createCalendarButton = () => {
  const button = document.createElement("button")
  button.type = "button"
  button.className =
    "absolute z-20 flex h-7 w-7 items-center justify-center rounded-md border border-base-content/18 bg-base-100/85 text-base-content/68 transition hover:border-primary/45 hover:text-primary"
  button.setAttribute("aria-label", "Abrir calendário")
  button.title = "Abrir calendário"
  button.innerHTML =
    '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-4"><path stroke-linecap="round" stroke-linejoin="round" d="M6.75 3v2.25m10.5-2.25v2.25M3 18.75V8.25A2.25 2.25 0 0 1 5.25 6h13.5A2.25 2.25 0 0 1 21 8.25v10.5A2.25 2.25 0 0 1 18.75 21H5.25A2.25 2.25 0 0 1 3 18.75ZM3 10.5h18" /></svg>'

  return button
}

const createNativePickerInput = (type) => {
  const picker = document.createElement("input")
  picker.type = type
  picker.tabIndex = -1
  picker.className =
    "pointer-events-none absolute z-10 cursor-pointer opacity-0"
  picker.setAttribute("aria-hidden", "true")
  return picker
}

const nextDatePickerControlId = (prefix) => {
  datePickerControlSequence += 1
  return `${prefix}-${datePickerControlSequence}`
}

const openNativePicker = (picker, textInput) => {
  const fallbackOpen = () => {
    picker.focus()
    picker.click()
  }

  try {
    if (typeof picker.showPicker === "function") {
      picker.showPicker()
    } else {
      fallbackOpen()
    }
  } catch (_) {
    fallbackOpen()
  }

  textInput.focus()
}

const ensureDateAnchorParent = (input) => {
  const parent = input.parentElement

  if (!(parent instanceof HTMLElement)) {
    return null
  }

  if (window.getComputedStyle(parent).position === "static") {
    parent.style.position = "relative"
    parent.dataset.datePickerPositioned = "true"
  }

  return parent
}

const positionDateControls = (input, button, picker) => {
  const controlSizePx = 28
  const controlPaddingPx = 4

  const leftPx = input.offsetLeft + input.offsetWidth - controlSizePx - controlPaddingPx
  const topPx = input.offsetTop + Math.max((input.offsetHeight - controlSizePx) / 2, 0)

  const left = `${Math.max(leftPx, 0)}px`
  const top = `${Math.max(topPx, 0)}px`
  const size = `${controlSizePx}px`

  button.style.left = left
  button.style.top = top
  button.style.width = size
  button.style.height = size

  picker.style.left = left
  picker.style.top = top
  picker.style.width = size
  picker.style.height = size

  if (typeof input.dataset.dateInputOriginalPaddingRight !== "string") {
    input.dataset.dateInputOriginalPaddingRight = window.getComputedStyle(input).paddingRight
  }

  input.style.paddingRight = `${controlSizePx + controlPaddingPx * 3}px`
}

const enhanceDateInput = (input, hook) => {
  if (!(input instanceof HTMLInputElement)) {
    return
  }

  if (input.dataset.datePickerBound === "true") {
    const button = document.getElementById(input.dataset.datePickerButtonId || "")
    const picker = document.getElementById(input.dataset.datePickerInputId || "")

    if (button instanceof HTMLButtonElement && picker instanceof HTMLInputElement) {
      positionDateControls(input, button, picker)
      return
    }

    delete input.dataset.datePickerBound
    delete input.dataset.datePickerButtonId
    delete input.dataset.datePickerInputId
  }

  if (input.dataset.datePickerBound === "true") {
    return
  }

  const mode = input.dataset.datePicker === "month" ? "month" : "date"
  const parent = ensureDateAnchorParent(input)

  if (!(parent instanceof HTMLElement)) {
    return
  }

  const picker = createNativePickerInput(mode)
  const button = createCalendarButton()
  button.id = nextDatePickerControlId("finance-date-picker-btn")
  picker.id = nextDatePickerControlId("finance-date-picker-input")

  parent.appendChild(picker)
  parent.appendChild(button)
  positionDateControls(input, button, picker)

  const syncPickerFromText = () => {
    picker.value =
      mode === "month" ? parsePtBrMonthToIso(input.value) : parsePtBrDateToIso(input.value)
  }

  const syncTextFromPicker = () => {
    const formatted = mode === "month" ? isoMonthToPtBr(picker.value) : isoDateToPtBr(picker.value)

    if (formatted !== "") {
      setInputValueAndNotify(input, formatted)
    }
  }

  const handleTextInput = () => {
    const masked = mode === "month" ? maskMonthInputValue(input.value) : maskDateInputValue(input.value)

    if (input.value !== masked) {
      input.value = masked
    }

    syncPickerFromText()
    positionDateControls(input, button, picker)
  }

  const handleButtonClick = () => {
    syncPickerFromText()
    openNativePicker(picker, input)
  }

  const handlePickerChange = () => {
    syncTextFromPicker()
  }

  const handleWindowResize = () => {
    positionDateControls(input, button, picker)
  }

  input.addEventListener("input", handleTextInput)
  button.addEventListener("click", handleButtonClick)
  picker.addEventListener("change", handlePickerChange)
  window.addEventListener("resize", handleWindowResize)

  handleTextInput()

  input.dataset.datePickerBound = "true"
  input.dataset.datePickerButtonId = button.id
  input.dataset.datePickerInputId = picker.id

  hook.cleanups.push(() => {
    input.removeEventListener("input", handleTextInput)
    button.removeEventListener("click", handleButtonClick)
    picker.removeEventListener("change", handlePickerChange)
    window.removeEventListener("resize", handleWindowResize)

    button.remove()
    picker.remove()

    if (typeof input.dataset.dateInputOriginalPaddingRight === "string") {
      input.style.paddingRight = input.dataset.dateInputOriginalPaddingRight
      delete input.dataset.dateInputOriginalPaddingRight
    }

    if (parent.dataset.datePickerPositioned === "true") {
      parent.style.position = ""
      delete parent.dataset.datePickerPositioned
    }

    delete input.dataset.datePickerBound
    delete input.dataset.datePickerButtonId
    delete input.dataset.datePickerInputId
  })
}

const enhanceFinanceFormInputs = (hook) => {
  hook.el.querySelectorAll(MONEY_SELECTOR).forEach((input) => {
    enhanceMoneyInput(input, hook)
  })

  hook.el.querySelectorAll(DATE_SELECTOR).forEach((input) => {
    enhanceDateInput(input, hook)
  })
}

const FinanceFormEnhancementsHook = {
  mounted() {
    this.cleanups = []
    enhanceFinanceFormInputs(this)
  },

  updated() {
    enhanceFinanceFormInputs(this)
  },

  destroyed() {
    this.cleanups.forEach((cleanup) => {
      cleanup()
    })

    this.cleanups = []
  },
}

export default FinanceFormEnhancementsHook
