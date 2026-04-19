# Integração entre Contexts, LiveViews, Componentes e Hooks

## Princípio de fronteira

- `Context` decide regra de negócio e persistência.
- `LiveView` coordena estado e eventos da tela.
- `Component` renderiza UI reutilizável.
- `Hook` resolve necessidades exclusivas do browser.

## Fluxo recomendado de implementação

1. **Domínio primeiro**
   - Criar/ajustar função no context.
   - Definir contrato de retorno (`{:ok, _} | {:error, _}`).
2. **Orquestração LiveView**
   - `handle_event/3` delega ao context.
   - Atualiza assigns e flash.
3. **Template/componentes**
   - IDs estáveis para elementos chave.
   - Inputs via `<.input>` e formulário com `to_form/2`.
4. **JS (se necessário)**
   - Comando `JS.*` ou hook com escopo mínimo.

## Padrão para adição de nova feature

- Definir rota/pipeline correta no `router.ex`.
- Garantir autenticação e `current_scope`.
- Implementar contexto + testes de domínio.
- Expor no LiveView + testes de interação.
- Ajustar componentes para visual e acessibilidade.

## Integração de eventos JS ↔ LiveView

- Cliente para servidor: `this.pushEvent("event", payload)` em hooks.
- Servidor para cliente: `push_event(socket, "event", payload)` + `handleEvent` (hook) ou `window` listener.
- Nomear eventos com semântica clara e evitar colisões globais.

Referências oficiais:

- https://hexdocs.pm/phoenix_live_view/js-interop.html
- https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html

## Checklist de integração

- Rota no escopo/pipeline correto.
- Regras no context correto.
- IDs e acessibilidade no template.
- Testes de domínio e LiveView atualizados.
- `mix precommit` verde.
