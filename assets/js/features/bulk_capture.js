export const BULK_DEFAULT_SELECTORS = {
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

const FIELD_PATTERNS = [
  "prioridade", "priority",
  "status",
  "horizonte", "horizon",
  "tipo", "kind",
  "natureza", "expense_profile",
  "pagamento", "payment_method",
]

const hasPrimaryModifier = (event) => event.ctrlKey || event.metaKey

export const resolveBulkShortcutAction = (event) => {
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

export const computeFieldAutocomplete = ({value, start, end}) => {
  if (typeof start !== "number" || typeof end !== "number" || start !== end) {
    return null
  }

  const source = value || ""
  const {lineStart, lineEnd} = currentLineBounds(source, start)
  const currentLine = source.slice(lineStart, lineEnd)

  const beforeCursor = currentLine.slice(0, start - lineStart)
  const fieldMatch = beforeCursor.match(/\b([a-z_]+)=([a-zA-Z]*)$/i)

  if (!fieldMatch) return null

  const fieldName = fieldMatch[1].toLowerCase()
  const prefix = fieldMatch[2]

  if (!FIELD_PATTERNS.includes(fieldName)) return null

  return {fieldName, prefix, lineStart, lineEnd, beforeCursor}
}

export const computeTypeAutocomplete = ({value, start, end}) => {
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
