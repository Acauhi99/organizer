# Organizer

Aplicação de organização pessoal com Phoenix (LiveView + API), SQLite e autenticação multiusuário.

## Estado atual da aplicação

- Autenticação web completa com `phx.gen.auth` (registro, login, sessão, recuperação de senha e configurações de conta).
- Dashboard LiveView em `/dashboard` com fluxo de operação diária e visão analítica.
- Importação em lote por texto no dashboard com:
	- templates rápidos (`mixed`, `tasks`, `finance`, `goals`)
	- pré-visualização, correções guiadas e importação incremental por bloco
	- histórico de payload, favoritos, modo estrito e desfazer última importação
- Operações de tarefas, finanças e metas no mesmo painel com filtros e edição inline.
- Classificação financeira por lançamento de despesa com natureza (`fixed`/`variable`) e forma de pagamento (`credit`/`debit`) no fluxo de captura rápida.
- Visão analítica com comparativos por período, capacidade planejada e indicadores de risco de sobrecarga.
- API REST em `/api/v1` para:
	- `tasks`
	- `finance-entries`
	- `goals`
	- `fixed-costs`
	- `important-dates`
- Isolamento por usuário em todas as consultas de domínio via `Scope`.

## Arquitetura

```mermaid
flowchart TD
		Browser[Cliente Web] --> Router[Phoenix Router]
		Router --> AuthPlugs[Auth plugs e current_scope]
		AuthPlugs --> Live[Dashboard LiveView]
		AuthPlugs --> Api[Controllers API v1]

		Live --> Planning[Organizer.Planning]
		Api --> Planning

		Planning --> Validation[AttributeValidation]
		Planning --> Analytics[Planning.Analytics]
		Planning --> Cache[AnalyticsCache GenServer]
		Planning --> Suggester[FieldSuggester GenServer]
		Planning --> Repo[Ecto Repo]
		Repo --> DB[(SQLite)]

		Cache --> ETS[(ETS :analytics_cache)]
		Cache --> Analytics
		Suggester --> ETS2[(ETS :field_suggestions)]

		Live --> Assets[assets/css + assets/js]
```

### Infraestrutura OTP

A aplicação utiliza padrões OTP para performance e escalabilidade:

- **AnalyticsCache (GenServer)**: Cache distribuído com ETS para cálculos de analytics. Fornece invalidação automática quando tarefas, finanças ou metas são alteradas. TTL de 5 minutos com fallback automático em cache miss.
  - Chave de cache: `analytics:user:{user_id}:days:{days}`
  - Acesso: `Organizer.Planning.AnalyticsCache.get_analytics/2`
  - Isolamento por usuário para segurança

- **FieldSuggester (GenServer)**: Sugestão de valores de campos baseada em frequência de uso por usuário. Armazena contadores de frequência e correlações entre campos em ETS. Fallback para valores canônicos estáticos quando não há histórico.
  - Tabela ETS: `:field_suggestions`
  - Acesso: `Organizer.Planning.FieldSuggester.suggest_values/2`, `complete/3`, `record_import/2`
  - Isolamento por usuário para segurança

- **Task.Supervisor**: Gerenciador de tarefas assíncronas para operações não-bloqueantes (email, bulk operations). Nomeado como `Organizer.TaskSupervisor`.
  - Uso: `Task.Supervisor.async_nolink(Organizer.TaskSupervisor, fn -> ... end)`

- **Phoenix.PubSub**: Sistema de pub/sub para broadcast de eventos (atualmente usado por LiveDashboard e telemetria).

## Dashboard

O dashboard (`/dashboard`) é a tela principal da aplicação e foi refatorado com foco em hierarquia visual, onboarding e configurabilidade.

### Hierarquia visual de três níveis

1. **Primário — Bulk Import Hero**: Componente de importação em lote com destaque máximo (40%+ da área visível em desktop). Superfície visual diferenciada com gradiente e borda de destaque.
2. **Secundário — Operations Panel**: Listagem e edição de tarefas, finanças e metas. Colapsável.
3. **Terciário — Analytics Panel**: Métricas e gráficos com carregamento assíncrono. Colapsável e oculto por padrão em mobile.

### Onboarding

Novos usuários são guiados por uma sequência de 5 passos ao acessar o dashboard pela primeira vez:

1. Boas-vindas e introdução ao Bulk Import
2. Formato de entrada (`tipo: conteúdo`)
3. Sistema de pré-visualização
4. Correções automáticas
5. Navegação pelos painéis secundários

O onboarding pode ser pulado a qualquer momento e retomado via menu de ajuda (`?`).

### Controles de visibilidade de painéis

O header do dashboard expõe controles para:

- Alternar visibilidade do Analytics Panel e Operations Panel
- Mudar o modo de layout:
  - **Expanded** (padrão): todos os painéis visíveis
  - **Focused**: apenas header + bulk import
  - **Minimal**: apenas bulk import

As preferências são persistidas por usuário entre sessões.

### Atalhos de teclado

| Atalho | Ação |
|--------|------|
| `Alt+B` | Focar no Bulk Import |
| `Alt+O` | Alternar Operations Panel |
| `Alt+A` | Alternar Analytics Panel |
| `Alt+F` | Ativar/desativar Focus Mode |
| `Esc` | Sair do Focus Mode |
| `?` | Abrir menu de ajuda / tutorial |

### Estados vazios educativos

Quando não há dados, cada painel exibe um estado vazio com exemplo de importação e botão para carregar o exemplo diretamente no editor.

## Dashboard

O dashboard (`/dashboard`) é a tela principal da aplicação com hierarquia visual de três níveis:

1. **Bulk Import Hero** (primário) — importação em lote com destaque máximo, sempre visível
2. **Operations Panel** (secundário) — tarefas, finanças e metas, colapsável
3. **Analytics Panel** (terciário) — métricas e gráficos, colapsável e oculto por padrão em mobile

### Onboarding

Novos usuários são guiados por 5 passos ao acessar o dashboard pela primeira vez. O progresso é persistido e o tutorial pode ser retomado via menu de ajuda (`?`).

### Controles de visibilidade e layout

O header expõe botões para alternar cada painel e três modos de layout:

| Modo | Painéis visíveis |
|------|-----------------|
| **Expanded** (padrão) | Todos |
| **Focused** | Header + Bulk Import |
| **Minimal** | Apenas Bulk Import |

### Atalhos de teclado

| Atalho | Ação |
|--------|------|
| `Alt+B` | Focar no Bulk Import |
| `Alt+O` | Alternar Operations Panel |
| `Alt+A` | Alternar Analytics Panel |
| `Alt+F` | Ativar/desativar Focus Mode |
| `Esc` | Sair do Focus Mode |
| `?` | Abrir menu de ajuda |

Guia completo: [docs/dashboard-user-guide.md](docs/dashboard-user-guide.md)

## Convenções de código e evolução

- Guia de inserção de novo código: [CODEBASE_GUIDELINES.md](CODEBASE_GUIDELINES.md)
- Diretrizes visuais e de componentes: [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)
- Planejamento de evolução do produto: [ROADMAP.md](ROADMAP.md)

## Rodando local (sem Docker)

- `mix setup`
- `mix phx.server` ou `iex -S mix phx.server`

Aplicação disponível em `http://localhost:4000`.

## Rodando com Docker

```bash
docker compose up --build
```

Aplicação em `http://localhost:4000`.

### Executando testes com Make

```bash
make test-domain
make test-web
make test-all
make run
```

Aliases de compatibilidade:

```bash
make test-unit
make test-stage2
```

Versão sem Docker (Mix local):

```bash
make test-domain-local
make test-web-local
make test-local-all
```

Banco local (dev):

```bash
make db-create
make db-migrate
make db-reset
```

### Suite unit-first (Docker)

```bash
sh scripts/tests/domain_suite.sh
```

Foco em regras de domínio (sem testes de integração web). O script imprime o tail e finaliza com `DOMAIN_EXIT:<code>`.

Atalho legado mantido: `sh scripts/test_unit.sh`.

### Suite focada da etapa web (Docker)

```bash
sh scripts/tests/web_suite.sh
```

O script imprime o tail dos testes e finaliza com `WEB_EXIT:<code>`.

Atalho legado mantido: `sh scripts/test_stage2.sh`.

## Deploy Fly.io (base)

Passo inicial de deploy manual:

1. Criar app e volume.
2. Configurar `SECRET_KEY_BASE`.
3. Executar `fly deploy`.

O runbook completo de operação e automação de pipeline ainda está em evolução (ver [ROADMAP.md](ROADMAP.md)).

## Referências Phoenix

- https://www.phoenixframework.org/
- https://hexdocs.pm/phoenix/overview.html
- https://hexdocs.pm/phoenix
