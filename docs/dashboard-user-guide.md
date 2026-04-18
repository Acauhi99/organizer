# Dashboard — Guia do Usuário

Este guia cobre as funcionalidades introduzidas no refactor de UX do dashboard: controles de visibilidade de painéis, modos de layout e atalhos de teclado.

---

## Visão geral do layout

O dashboard é organizado em três níveis de hierarquia visual:

1. **Bulk Import Hero** (primário) — área central de importação em lote, sempre visível
2. **Operations Panel** (secundário) — listagem e edição de tarefas, finanças e metas
3. **Analytics Panel** (terciário) — métricas e gráficos, colapsável

---

## Onboarding

Na primeira vez que você acessa o dashboard, uma sequência guiada de 5 passos é exibida:

| Passo | Conteúdo |
|-------|----------|
| 1 | Boas-vindas e introdução ao Bulk Import |
| 2 | Formato de entrada (`tipo: conteúdo`) |
| 3 | Sistema de pré-visualização |
| 4 | Correções automáticas de linhas |
| 5 | Navegação pelos painéis secundários |

- Use **Próximo** / **Anterior** para navegar entre os passos.
- Clique em **Pular** a qualquer momento para fechar o onboarding.
- Para reabrir o tutorial, pressione `?` ou clique no ícone de ajuda no header.

---

## Controles de visibilidade de painéis

Os controles ficam no header do dashboard, à direita.

### Alternar painéis individuais

| Botão | Ação |
|-------|------|
| **Analytics** | Mostra ou oculta o Analytics Panel |
| **Operações** | Mostra ou oculta o Operations Panel |

O estado de cada painel é salvo automaticamente e restaurado na próxima sessão.

### Modos de layout

Três modos controlam quais painéis são exibidos simultaneamente:

| Modo | O que é exibido |
|------|-----------------|
| **Expanded** (padrão) | Header + Bulk Import + Operations + Analytics |
| **Focused** | Header + Bulk Import |
| **Minimal** | Apenas Bulk Import |

Clique no ícone do modo desejado nos controles do header para alternar. A preferência é persistida entre sessões.

**Exemplo de uso:** ative o modo **Focused** quando quiser importar um lote grande sem distrações, e volte para **Expanded** depois.

---

## Atalhos de teclado

| Atalho | Ação |
|--------|------|
| `Alt+B` | Move o foco para o campo de texto do Bulk Import |
| `Alt+O` | Alterna visibilidade do Operations Panel |
| `Alt+A` | Alterna visibilidade do Analytics Panel |
| `Alt+F` | Ativa o Focus Mode (oculta painéis secundários) |
| `Esc` | Sai do Focus Mode |
| `?` | Abre o menu de ajuda / reinicia o tutorial |

**Exemplo:** para importar rapidamente sem usar o mouse, pressione `Alt+B` para focar o editor, cole o texto, pressione `Tab` até o botão de pré-visualização e confirme com `Enter`.

---

## Estados vazios educativos

Quando um painel não tem dados, ele exibe um exemplo de importação para aquele tipo de entidade. Clique em **Carregar exemplo no editor** para preencher o Bulk Import com linhas de exemplo prontas para editar e importar.

---

## Navegação por teclado (acessibilidade)

- Use `Tab` para navegar entre todos os elementos interativos na ordem da hierarquia visual.
- Skip links no topo da página permitem pular diretamente para o Bulk Import, Operations Panel ou Analytics Panel.
- Todos os botões de toggle possuem labels acessíveis anunciados por leitores de tela.

---

## Solução de problemas

**O onboarding não aparece mais e quero rever o tutorial.**
Pressione `?` ou clique no ícone de ajuda no header para reiniciar a sequência.

**Ocultei um painel e não sei como restaurar.**
Clique no botão correspondente (**Analytics** ou **Operações**) nos controles do header, ou use os atalhos `Alt+A` / `Alt+O`.

**O modo de layout mudou e não sei como voltar.**
Clique no ícone **Expanded** (primeiro ícone de modo) nos controles do header para restaurar o layout padrão.

**Os gráficos do Analytics Panel aparecem como esqueleto por muito tempo.**
Os gráficos carregam de forma assíncrona após a renderização inicial. Se o carregamento demorar mais que alguns segundos, recarregue a página.
