# Design System Organizer

## Objetivo
Padronizar aparência e comportamento visual da plataforma em dark mode fixo, com foco em legibilidade, hierarquia e consistência entre páginas.

## Fundamentos
- Tema único: `dark` (daisyUI)
- Tipografia:
  - Títulos e conteúdo: `Space Grotesk`
  - Navegação, labels e botões: `IBM Plex Mono`
- Paleta principal:
  - Primário: gradiente cyan + emerald
  - Superfícies: variações de `base-100` com transparência
  - Feedback: `info/success/warning/error` do tema dark

## Componentes de Superfície (CSS)
Definidos em `assets/css/app.css`:
- `.surface-card`: cartão padrão com borda, blur e sombra
- `.micro-surface`: cartão secundário (blocos menores)
- `.brand-hero-card`: bloco de destaque para hero/boas-vindas

## Navegação
- `.site-nav`: barra superior com sombra discreta
- `.brand-mark` + `.brand-wordmark`: marca visual do produto
- `.identity-pill`: chip de identidade do usuário
- `.top-nav-link`: links de navegação em formato pill
- `.header-cta`: botão de ação no header interno

## Botões
- Base: `.btn`
- Variações principais:
  - `.btn-primary`: ação principal
  - `.btn-soft`: ação secundária
  - `.btn-outline`: ação de suporte
- Componente Phoenix `<.button>` aplica `.ui-btn` automaticamente

## Formulários
- Inputs/select/textarea com foco padronizado e bordas consistentes
- Labels em caixa alta, tracking leve e contraste adequado

## Dashboard (classes utilitárias)
- `.dashboard-shell`: contexto de estilo do painel
- `.ds-pill-btn`: botões de chip/preset
- `.ds-inline-btn`: ação inline padrão
- `.ds-inline-btn-danger`: ação inline destrutiva
- `.ds-edit-form`: contêiner de edição inline
- `.ds-empty-state`: estado vazio padronizado

## Componentes Base Phoenix
Refinados em `lib/organizer_web/components/core_components.ex`:
- Flash com superfície e sombra consistentes
- Botão com variantes `primary | soft | outline`
- Inputs e labels alinhados ao sistema
- Tabela/lista com superfícies dark e hover consistente

## Regras de uso
- Sempre preferir as classes de sistema antes de inventar classes locais.
- Evitar hardcode de cores (`text-slate-*`, `bg-white`) fora de contexto visual específico.
- Para novas telas:
  1. Estrutura com `.surface-card` ou `.brand-hero-card`
  2. Ações com `.btn-primary` e fallback `.btn-soft`
  3. Campos com `<.input>` do CoreComponents
  4. Estados vazios com `.ds-empty-state`

## Assets de marca
- Logo: `priv/static/images/organizer-logo.svg`
- Favicon: `priv/static/favicon.svg`

## Observação
A plataforma usa dark mode fixo. Não existe alternância light/dark.
