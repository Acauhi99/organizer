const setKeyboardMode = () => {
  document.body.classList.add("keyboard-nav-active")
}

const unsetKeyboardMode = () => {
  document.body.classList.remove("keyboard-nav-active")
}

export const registerKeyboardNavigationIndicators = ({target = document} = {}) => {
  const onKeyDown = (event) => {
    if (event.key === "Tab") {
      setKeyboardMode()
    }
  }

  target.addEventListener("keydown", onKeyDown)
  target.addEventListener("mousedown", unsetKeyboardMode)

  return () => {
    target.removeEventListener("keydown", onKeyDown)
    target.removeEventListener("mousedown", unsetKeyboardMode)
  }
}
