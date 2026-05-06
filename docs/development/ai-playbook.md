# Guia de Execução para Agentes (AI Playbook)

Objetivo: permitir implementação/ajuste com baixo risco arquitetural e alta consistência visual.

## Ordem recomendada

1. Ler [Arquitetura](../architecture.md) e [Integração](integration-patterns.md).
2. Localizar fluxo no `router.ex` e context alvo.
3. Implementar domínio primeiro.
4. Orquestrar web (LiveView/controller).
5. Aplicar UI no padrão Tailwind-first + Neon Grid.
6. Atualizar docs do escopo alterado.

## Princípios obrigatórios

- Regra de negócio no context.
- Isolamento por `current_scope`.
- JS mínimo e funcional, apenas para browser capabilities.
- Mudanças pequenas, rastreáveis e reversíveis.
- Sem abstração genérica sem necessidade concreta.

## Critérios de design de código

- Nomes orientados ao domínio (`create_*`, `update_*`, `refresh_*`, `parse_*`).
- Eventos LiveView semânticos.
- Funções privadas curtas e focadas.
- Evitar anti-patterns de Elixir (`String.to_atom/1` em input externo, `try/rescue` para fluxo comum, `with else` complexo).

## LiveView e JS (operacional)

- LiveView é fonte de verdade de estado.
- `Phoenix.LiveView.JS` para interações imediatas de UI.
- `phx-hook` para browser API e integração externa.
- Listeners globais só quando evento é realmente global.

## Definition of done (estado atual)

1. Regras de domínio no context correto.
2. Rotas/autenticação no escopo correto.
3. UI aderente ao tema Neon Grid com legibilidade alta.
4. JS com fronteira de efeitos explícita e cleanup.
5. Validação local: `mix format`, `mix compile --warnings-as-errors`, `mix xref ...`.
6. Docs de `docs/` atualizadas.

## Nota sobre testes

Suíte `test/**` removida temporariamente durante refactor visual. Reintrodução será incremental por fluxo crítico após estabilização do redesign.
