# Design System

## Direção visual

- Tema base dark, com foco em legibilidade e contraste.
- Tipografia principal:
  - `Space Grotesk` para conteúdo/títulos
  - `IBM Plex Mono` para labels/ações
- Estilo geral: superfícies translúcidas, hierarquia clara e microinterações discretas.

## Stack de estilo

- Tailwind CSS v4 com classes inline nos templates HEEx
- daisyUI vendorizado em `assets/vendor`
- CSS puro residual em `assets/css/app.css` para casos onde Tailwind não cobre bem

## Regras obrigatórias

1. Preferir utilitários Tailwind inline no template.
2. Não usar `@apply`.
3. Não criar classes semânticas novas sem necessidade técnica real.
4. Manter consistência com componentes base (`<.button>`, `<.input>`, etc).

## CSS puro residual permitido

- `color-mix()` com variáveis de tema
- pseudo-elementos (`::before`, `::after`)
- animações `@keyframes`
- estilos de SVG gerado por biblioteca externa (ex.: Contex)

## Classes de referência no projeto

- Superfícies: `.surface-card`, `.micro-surface`, `.brand-hero-card`
- Ações: `.btn-primary`, `.btn-soft`, `.btn-outline`, `.ds-pill-btn`
- Acessibilidade: `.skip-link`, `.keyboard-nav-active`

## Acessibilidade visual

- Indicadores claros de foco visível
- Suporte a navegação por teclado com skip links
- Respeito a `prefers-reduced-motion` nas animações
