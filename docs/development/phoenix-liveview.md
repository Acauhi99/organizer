# Boas Práticas Phoenix LiveView

## Fonte de verdade de estado

No Organizer, estado de tela e comportamento de negócio ficam no LiveView/context, não no JavaScript.

- LiveView recebe eventos de UI (`handle_event/3`)
- Context executa regra de negócio
- LiveView reatribui estado via assigns

Referências oficiais:

- LiveView welcome: https://hexdocs.pm/phoenix_live_view/welcome.html
- LiveView bindings: https://hexdocs.pm/phoenix_live_view/bindings.html

## Roteamento e autenticação

- Use pipelines e `live_session` para separar áreas autenticadas.
- Garanta `current_scope` em rotas e consultas.
- Em páginas protegidas, rota deve estar sob sessão autenticada.

Referência:

- Phoenix routing: https://hexdocs.pm/phoenix/routing.html

## Componentização

- Use function components para UI reutilizável.
- Mantenha componentes sem regra de domínio.
- IDs estáveis em elementos interativos para automação e QA.

## Formulários

- Construa formulário com `to_form/2` no LiveView.
- No template, use `<.form for={@form}>` e `<.input field={@form[:campo]}>`.
- Não renderize changeset direto no template.

## Streams

- Use streams para listas grandes e mutáveis.
- Use `phx-update="stream"` no container pai.
- Cada item precisa de id estável.

Referência:

- https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html

## Estilo de UI

- Tailwind-first: estilo majoritariamente inline no HEEx.
- Tema global Neon Grid (`organizer_neon_grid`) como baseline.
- Motion discreto + contraste alto + foco visível.

## Eventos de teclado

- Para atalhos globais, use `phx-window-keydown`.
- Se precisar de `altKey`/`metaKey`, configure `metadata.keydown` no `LiveSocket`.
- Tenha fallback para payload sem `"key"`.
