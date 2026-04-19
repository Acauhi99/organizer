# Features

## Núcleo do produto

- Dashboard diário em `/dashboard` com hierarquia visual em três blocos:
  - Bulk Import Hero
  - Operations Panel
  - Analytics Panel
- Captura e gestão de:
  - Tarefas
  - Lançamentos financeiros
  - Metas

## Importação em lote

- Entrada por texto estruturado
- Templates rápidos por tipo de entidade
- Pré-visualização antes de persistir
- Correções automáticas e fluxo incremental por bloco
- Histórico de payloads e favoritos
- Modo estrito (bloqueia importação com erros)
- Desfazer última importação

## Analytics e capacidade

- Comparativos semanal/mensal/anual
- Burndown e capacidade planejada
- Indicadores de risco de sobrecarga/burnout
- Gráficos SVG gerados no servidor (Contex)

## Colaboração financeira

- Fluxo de convite e vínculo entre contas
- Visualização de finanças compartilhadas
- Fluxo de acerto (settlement)

## Autenticação e segurança

- Fluxo de registro/login/logout
- Sessão autenticada com escopo de usuário
- Isolamento de dados por `current_scope`

## API REST (`/api/v1`)

Recursos disponíveis:

- `tasks`
- `finance-entries`
- `goals`
- `fixed-costs`
- `important-dates`

Todas as rotas exigem autenticação e escopo válido.
