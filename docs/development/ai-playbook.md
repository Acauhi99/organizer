# Guia de Execução para Agentes (AI Playbook)

Objetivo: permitir que qualquer agente novo no repositório consiga implementar features e corrigir bugs com baixo risco de regressão.

## Ordem de trabalho recomendada

1. Ler [Arquitetura](../architecture.md) e [Integração entre camadas](integration-patterns.md).
2. Localizar o fluxo no router (`lib/organizer_web/router.ex`) e no context alvo.
3. Implementar primeiro no domínio (context), depois orquestração web (LiveView/controller), depois UI.
4. Criar/atualizar testes no mesmo PR.
5. Rodar validação local completa antes de finalizar.

## Princípios obrigatórios

- Priorizar função pura e transformação explícita de dados.
- Evitar mover regra de negócio para camada de apresentação.
- Respeitar isolamento por usuário via `current_scope`.
- Preferir mudanças pequenas, testáveis e reversíveis.
- Não introduzir abstrações genéricas sem necessidade clara.

## Critérios de design de código

- Nomes orientados a intenção de negócio (`create_*`, `update_*`, `refresh_*`, `parse_*`).
- Eventos LiveView com semântica de ação do usuário.
- Funções privadas curtas, com única responsabilidade.
- Evitar anti-patterns conhecidos de Elixir (`String.to_atom/1` com input externo, `try/rescue` para fluxo comum, `with` com `else` complexo).

Referências oficiais:

- https://hexdocs.pm/elixir/main/code-anti-patterns.html
- https://hexdocs.pm/elixir/main/design-anti-patterns.html

## LiveView e JS (resumo operacional)

- Use LiveView como fonte de verdade de estado.
- Use `Phoenix.LiveView.JS` para interações imediatas de UI sem round-trip.
- Use `phx-hook` quando precisar de API do browser ou integração com biblioteca JS.
- Evite listeners globais quando um hook local ou JS command resolver.

Referências oficiais:

- https://hexdocs.pm/phoenix_live_view/bindings.html
- https://hexdocs.pm/phoenix_live_view/js-interop.html
- https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html

## Definition of done para agentes

Uma entrega só está concluída quando:

1. Regras de domínio foram implementadas no context correto.
2. Rotas/autenticação estão no escopo correto.
3. Componentes/LiveViews possuem IDs estáveis para teste.
4. Testes de sucesso e falha foram atualizados.
5. `mix precommit` passou sem falhas.
6. Documentação em `docs/` foi atualizada se houve mudança de comportamento.
