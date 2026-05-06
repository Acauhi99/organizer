# Integração entre Contexts, LiveViews, Componentes e Hooks

## Fronteira

- `Context`: regra de negócio + persistência.
- `LiveView`: estado da tela + orquestração de eventos.
- `Component`: UI reutilizável.
- `Hook`: necessidade estrita de browser.

## Fluxo recomendado

1. Domínio primeiro
- Criar/ajustar função no context.
- Definir contrato de retorno (`{:ok, _} | {:error, _}`).

2. Orquestração LiveView/controller
- Delegar ao context.
- Atualizar assigns/flash.

3. Template/componentes
- IDs estáveis para elementos chave.
- Inputs via `<.input>` e formulário via `to_form/2`.

4. JS (se necessário)
- Preferir `JS.*`.
- Se hook, manter escopo mínimo e cleanup explícito.

## Padrão para nova feature

- Definir rota/pipeline correta em `router.ex`.
- Garantir autenticação e `current_scope`.
- Implementar contexto.
- Expor no LiveView/controller.
- Aplicar padrão visual Tailwind-first + Neon Grid.
- Validar com `format + compile + xref` e revisão visual.

## Eventos JS ↔ LiveView

- Cliente -> servidor: `this.pushEvent("event", payload)`.
- Servidor -> cliente: `push_event(socket, "event", payload)` + `handleEvent` no hook ou listener global.
- Nomear eventos com semântica clara e evitar colisões.

Referências oficiais:

- https://hexdocs.pm/phoenix_live_view/js-interop.html
- https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html

## Checklist

- Rota no escopo/pipeline correto.
- Regras no context correto.
- Contraste/foco/motion acessíveis no template.
- Hook com cleanup (se existir).
- Docs em `docs/` atualizadas quando comportamento muda.
