# JavaScript Funcional no Contexto LiveView

## Regra geral

Use o mínimo de JavaScript possível.

- Primeiro tente resolver com LiveView puro.
- Depois com `Phoenix.LiveView.JS` (comandos declarativos).
- Use hooks somente para capacidades exclusivas do browser.

Referências oficiais:

- JS commands: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html
- JS interop/hooks: https://hexdocs.pm/phoenix_live_view/js-interop.html
- Bindings: https://hexdocs.pm/phoenix_live_view/bindings.html

## Quando usar cada abordagem

### 1. `Phoenix.LiveView.JS`

Para interações imediatas de UI sem lógica complexa:

- `show/hide/toggle`
- `add_class/remove_class`
- `focus`
- `dispatch`

### 2. Hook (`phx-hook`)

Para:

- APIs de browser (`clipboard`, `geolocation`, etc.)
- integração com libs JS de terceiros
- manipulação avançada de input no cliente

### 3. Listener global (`window.addEventListener("phx:*")`)

Apenas quando o evento for realmente global para a página inteira.

## Estilo funcional em JS no projeto

- Prefira funções puras para parsing/autocomplete (`input -> output`).
- Minimize efeitos colaterais e centralize listeners.
- Sempre faça cleanup no `destroyed()` do hook.
- Evite estado implícito global quando o estado pode viver no elemento hookado.

## Cuidados com DOM patching

- Se uma biblioteca controla DOM internamente, use `phx-update="ignore"` no container.
- Lembre que hooks têm ciclo de vida (`mounted`, `updated`, `destroyed`, `disconnected`, `reconnected`).

Referência oficial:

- https://hexdocs.pm/phoenix_live_view/bindings.html
