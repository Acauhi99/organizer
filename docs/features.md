# Features

## Área pública (não logada)

- Página inicial em `/` com resumo dos fluxos ativos do produto:
  - Importação rápida por texto
  - Operação diária (tarefas + lançamentos financeiros)
  - Colaboração financeira por convite entre contas
- Fluxos de autenticação:
  - Cadastro em `/users/register`
  - Login em `/users/log-in`
  - Contexto especial quando há convite pendente de vínculo

## Dashboard autenticado (`/dashboard`)

- Cabeçalho com KPIs de burndown e saldo financeiro.
- Painéis de lançamento rápido:
  - Formulário de tarefas
  - Formulário de renda/gastos (com opção de compartilhamento em vínculo ativo)
- Painel de vínculo entre contas:
  - Criação de convite
  - Acesso à área de finanças compartilhadas e acerto
- Importação em lote por texto:
  - Pré-visualização por linha
  - Correções guiadas
  - Importação por bloco ou total
  - Modo estrito
  - Histórico de payloads e favoritos
  - Desfazer última importação
- Operação diária com listas filtráveis de tarefas e lançamentos.
- Analytics com comparativos semanal/mensal/anual, tendência de saldo e categorias de despesa.

## Colaboração financeira

- Vínculo entre duas contas por convite (`/account-links`).
- Visão de finanças compartilhadas por vínculo (`/account-links/:link_id`).
- Fluxo de acerto com registros de transferência e confirmação bilateral (`/account-links/:link_id/settlement`).

## Domínio e API REST (`/api/v1`)

Recursos disponíveis:

- `tasks`
- `finance-entries`
- `goals`
- `fixed-costs`
- `important-dates`

Notas:

- As rotas da API exigem autenticação e escopo válido.
- O dashboard atual prioriza tarefas e finanças; `goals`, `fixed-costs` e `important-dates` estão disponíveis no domínio e na API.

## Autenticação e segurança

- Registro, login e logout com sessão autenticada.
- Isolamento de dados por `current_scope`.
- Redirecionamentos de proteção em rotas autenticadas.
