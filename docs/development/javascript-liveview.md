# JavaScript Funcional no Contexto LiveView

## Objetivo

Manter integração LiveView estável com JS mínimo, previsível e fácil de remover.

Ordem de decisão:

1. Resolver no servidor (LiveView).
2. Resolver com `Phoenix.LiveView.JS`.
3. Usar hook/listener JS só quando browser API ou comportamento local exigir.

Referências oficiais:

- JS commands: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html
- JS interop/hooks: https://hexdocs.pm/phoenix_live_view/js-interop.html
- Bindings: https://hexdocs.pm/phoenix_live_view/bindings.html

## Contrato funcional adotado no projeto

### 1) Fronteira de efeitos explícita

- Funções puras: parse, normalização, decisão (`input -> output`).
- Efeitos (DOM, timers, storage, network) só em funções de borda.
- Padrão obrigatório para listeners globais: `registerX(...) -> cleanup`.

Exemplo real no projeto:

- `registerScrollToElementListener()` retorna função de limpeza.
- `initializeFlashAutoDismiss()` arma observer e retorna cleanup.

### 2) Estado local por hook

- Estado vive em `this.state` dentro do hook.
- Nunca usar estado global implícito para fluxo do hook.
- `mounted`: cria estado + wiring.
- `updated`: re-sincroniza sem duplicar listeners.
- `destroyed`: sempre executa cleanup completo.

### 3) Wiring centralizado

- `assets/js/app.js` é ponto único de bootstrap.
- `app.js` compõe:
  - `buildLiveSocket`
  - bindings de topbar
  - features globais (`phx:*`)
  - modo dev (live reload shortcuts)

Isso reduz acoplamento e facilita rastrear side effects.

## Quando usar cada abordagem

### `Phoenix.LiveView.JS`

Use para UI declarativa curta:

- `show/hide/toggle`
- `add_class/remove_class`
- `focus`
- `dispatch`

### Hook (`phx-hook`)

Use quando precisa:

- browser API (`Notification`, `Clipboard`, etc.)
- integração com libs JS externas
- comportamento de input rico no cliente

### Listener global (`window.addEventListener("phx:*")`)

Use só para evento de página inteira.
Sempre registrar em função dedicada e retornar cleanup.

## Regras de estabilidade com LiveView

- Nunca injetar `<script>` inline em HEEx.
- Se JS externo controla subtree de DOM, usar `phx-update="ignore"` no container.
- Não assumir que nó DOM persiste entre patches.
- Em `updated`, evitar rebind cego de listeners.

## Checklist para novo JS

- Existe versão sem JS? Se sim, preferir.
- Efeito está isolado em função de borda?
- Hook/listener retorna cleanup?
- Estado está explícito (`this.state`) e local?
- Nome do evento (`phx:*` ou custom) está documentado no módulo?
- Funciona após patch de LiveView (`updated`) e teardown (`destroyed`)?
