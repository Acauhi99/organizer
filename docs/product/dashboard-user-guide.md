# Dashboard — Guia do Usuário

Este guia cobre os fluxos atuais do dashboard autenticado (`/dashboard`): lançamentos rápidos, importação em lote, operação diária, analytics, vínculo entre contas e onboarding.

## Visão geral do layout

1. **Header com KPIs**: burndown (14d), receitas, despesas e saldo.
2. **Vínculo entre contas**: convite, gestão de vínculo e atalhos para colaboração financeira.
3. **Lançamento rápido de finanças**: cadastro de renda/gastos por formulário.
4. **Lançamento rápido de tarefas**: cadastro com prioridade, status, prazo e notas.
5. **Importação rápida por texto**: preview, correções e importação em lote.
6. **Operação diária**: listas filtráveis de tarefas e lançamentos.
7. **Visão analítica**: comparativos, tendências e risco operacional.

## Lançamentos rápidos

- **Finanças**:
  - Presets para renda e gastos.
  - Campos de tipo, valor, data, categoria e detalhes de despesa.
  - Em vínculo ativo, permite compartilhar despesa e escolher modo de divisão.
- **Tarefas**:
  - Presets de contexto (foco, próxima ação, backlog, etc.).
  - Campos de prioridade, status, prazo e notas.

## Onboarding

Na primeira visita ao dashboard, há uma sequência guiada de 6 passos cobrindo os blocos principais:

1. Boas-vindas e visão geral
2. Lançamento rápido
3. Filtros operacionais
4. Edição direta na operação
5. Painéis de operação e analytics
6. Área de vínculo entre contas

- Use **Próximo** / **Anterior**.
- Clique em **Pular** para encerrar.
- Para reabrir, pressione `?` ou use o menu de ajuda.

## Importação em lote por texto

- Entrada no padrão `tipo: conteúdo`.
- Suporte a preview antes de persistir.
- Correção por linha e correção em lote.
- Importação por bloco ou completa.
- Histórico recente de payloads e favoritos.
- Modo estrito para bloquear importações com erro.
- Opção de desfazer a última importação.

## Operação diária e analytics

- **Operação diária**:
  - Aba de tarefas com checklist por item.
  - Aba de finanças com filtros por tipo, perfil, método, categoria e valor.
- **Analytics**:
  - Execução por período (semanal, mensal, anual).
  - Tendência de saldo semanal.
  - Top categorias de despesa.
  - Snapshot de capacidade e sinalização de risco.

## Área de vínculo entre contas

- Sem vínculo ativo: ações para criar convite e abrir gestão de vínculos.
- Com vínculo ativo: atalhos para finanças compartilhadas e acerto.

## Atalhos de teclado

| Atalho | Ação |
|--------|------|
| `Alt+B` | Foca o editor do Bulk Import |
| `?`     | Abre ajuda / reinicia tutorial |

## Estados vazios educativos

Quando não há dados em um painel, o sistema mostra exemplos e oferece carregamento direto no editor.

## Acessibilidade

- Navegação completa por `Tab`
- Skip links para seções principais
- Labels e papéis ARIA nos controles principais

## Solução de problemas

**Onboarding não aparece mais**

Use `?` ou menu de ajuda para reiniciar.

**Analytics com skeleton por muito tempo**

Recarregue a página e confira conectividade.
