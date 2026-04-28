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

Referências oficiais:

- Phoenix routing: https://hexdocs.pm/phoenix/routing.html

## Componentização

- Use function components para UI reutilizável.
- Mantenha componentes sem regra de domínio.
- IDs estáveis em elementos interativos para testes LiveView.

## Formulários

- Construa formulário com `to_form/2` no LiveView.
- No template, use `<.form for={@form}>` e `<.input field={@form[:campo]}>`.
- Não renderize changeset direto no template.

## Streams

- Use streams para listas grandes e mutáveis.
- Use `phx-update="stream"` no container pai.
- Cada item precisa de id estável.

Referências oficiais:

- LiveView streams API: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html

## Paginação

- Use sempre o wrapper `<.pagination>` de `CoreComponents` para manter o mesmo visual e acessibilidade.
- O estado de página deve ser explícito no LiveView (`:page` por lista) e sincronizado via `handle_params/3` quando houver query string.
- Em filtros que mudam o conjunto, resete a página para `1` para evitar telas vazias em páginas altas.
- Sempre exiba meta de progresso de paginação (`Página X de Y`) para orientar o usuário.

## Eventos de teclado

- Para atalhos globais, use `phx-window-keydown`.
- Se precisar de `altKey`/`metaKey`, configure `metadata.keydown` no `LiveSocket`.
- Tenha fallback para payload sem `"key"`.

Referência oficial:

- https://hexdocs.pm/phoenix_live_view/bindings.html
