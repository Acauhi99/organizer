# Arquitetura

## Visão macro

O Organizer é uma aplicação Phoenix com dois canais principais de entrada:

- Interface web com LiveView (`/dashboard` e fluxos de vínculo entre contas)
- API REST (`/api/v1`) para operações de domínio

Ambos convergem para contexts de domínio que aplicam regras de negócio com isolamento por usuário (`current_scope`).

## Fluxo de camadas

```mermaid
flowchart TD
  Browser[Browser] --> Router[Phoenix Router]
  Router --> Auth[UserAuth + current_scope]
  Auth --> Live[LiveViews e Components]
  Auth --> API[Controllers API v1]

  Live --> Planning[Organizer.Planning]
  API --> Planning

  Live --> SharedFinance[Organizer.SharedFinance]
  API --> SharedFinance

  Planning --> Repo[Ecto Repo]
  SharedFinance --> Repo
  Repo --> DB[(SQLite)]

  Planning --> AnalyticsCache[AnalyticsCache GenServer + ETS]
  Planning --> FieldSuggester[FieldSuggester GenServer + ETS]
```

## Módulos principais

### Web

- `lib/organizer_web/router.ex`: roteamento e boundaries de autenticação
- `lib/organizer_web/live/*.ex`: LiveViews de dashboard e finanças compartilhadas
- `lib/organizer_web/components/*.ex`: function components reutilizáveis
- `assets/js/app.js`: hooks e interop JS do LiveView

### Domínio

- `lib/organizer/planning.ex`: tarefas, finanças, metas, analytics e bulk import
- `lib/organizer/shared_finance.ex`: vínculo de contas e colaboração financeira
- `lib/organizer/accounts.ex`: autenticação, usuários e preferências

### Infra OTP

- `Organizer.Planning.AnalyticsCache`: cache de analytics por usuário (ETS)
- `Organizer.Planning.FieldSuggester`: sugestões/autocomplete por histórico (ETS)
- `Organizer.TaskSupervisor`: tarefas assíncronas com isolamento por processo

## Roteamento e autenticação

A estratégia segue o padrão oficial de pipelines Phoenix + `live_session` para LiveView autenticado:

- Pipeline `:browser` com `fetch_current_scope_for_user`
- `live_session :authenticated` para páginas LiveView protegidas
- Pipeline `:api` + `:require_authenticated_api_user` para API REST

Referências oficiais:

- Phoenix routing: https://hexdocs.pm/phoenix/routing.html
- LiveView welcome/lifecycle: https://hexdocs.pm/phoenix_live_view/welcome.html

## Diretriz arquitetural obrigatória

1. Regra de negócio pertence aos contexts, não a controllers/components.
2. LiveView orquestra estado de tela e delega ao contexto.
3. JS existe para capacidades de browser, não para substituir estado de domínio.
4. Toda consulta mutável/leitura sensível deve respeitar `current_scope`.
