export const registerKeyboardNavigationIndicators = () => {
  document.addEventListener("keydown", (event) => {
    if (event.key === "Tab") {
      document.body.classList.add("keyboard-nav-active")
    }
  })

  document.addEventListener("mousedown", () => {
    document.body.classList.remove("keyboard-nav-active")
  })
}
