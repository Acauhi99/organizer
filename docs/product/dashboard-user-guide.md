# Dashboard — Guia do Usuário

Este guia cobre os fluxos autenticados atuais da aplicação: módulo de finanças (`/finances`) e colaboração financeira (`/account-links`).

## Visão geral

1. **Módulo de finanças (`/finances`)**:
  - lançamento rápido de receita/despesa
  - métricas e gráficos financeiros
  - operação diária com filtros e edição inline
2. **Colaboração (`/account-links`)**:
  - criação e aceite de convite
  - finanças compartilhadas por vínculo
  - acerto mensal com confirmação bilateral (na mesma tela do vínculo)

## Lançamentos rápidos

### Finanças (`/finances`)

- Presets para entradas de renda e despesa.
- Campos de tipo, valor, data, categoria e descrição.
- Para despesas, suporte a perfil, método de pagamento e parcelas.
- Com vínculo ativo, opção de compartilhar despesa:
  - modo `income_ratio`
  - modo `manual` (definição da parcela de cada lado)

## Operação diária

### Finanças

- Filtros por período (janela móvel, data específica, mês, intervalo e dia da semana).
- Filtros por tipo, categoria, método, perfil, texto e faixa de valor.
- Edição e exclusão de lançamentos direto na lista.

## Métricas e analytics

### Finanças

- KPIs de saldo, ticket médio, categoria dominante e volume do período.
- Gráficos de fluxo, composição e ranking por categoria.

## Onboarding

Na primeira experiência autenticada, o sistema exibe onboarding em 6 passos cobrindo os blocos principais:

1. Visão geral
2. Lançamento rápido
3. Filtros operacionais
4. Edição direta
5. Métricas
6. Colaboração

- Use **Próximo** / **Anterior**.
- Clique em **Pular** para encerrar.

## Colaboração financeira

- `/account-links`: lista de vínculos ativos e atalhos para cada vínculo.
- `/account-links/invite`: gerar e copiar link de convite; aceitar convite por token.
- `/account-links/:link_id`: tela unificada com:
  - resumo compartilhado e tendências
  - lançamentos compartilhados
  - pagamentos/transferências do acerto
  - resumo mensal de dívidas e confirmação bilateral

## Atalhos de teclado

| Atalho | Ação |
|--------|------|
| `Alt+B` | Rola para o lançamento rápido financeiro |
| `?`     | Exibe lembrete de atalhos |

## Acessibilidade

- Skip links para seções principais dos módulos.
- Navegação por teclado em formulários e painéis.
- Estrutura com labels e ARIA nos componentes críticos.
