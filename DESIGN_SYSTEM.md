# Design System Organizer

## Objetivo
Padronizar aparência e comportamento visual da plataforma em dark mode fixo, com foco em legibilidade, hierarquia e consistência entre páginas.

## Fundamentos
- Tema único: dark (daisyUI via plugin vendorizado em `assets/vendor/`)
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

## Area publica (nao logada)
Padrao aplicado em Home, Cadastro, Login e Recuperacao de senha:
- Layout: `.public-auth-shell` com grid de dois cards e `wide={true}` no `<Layouts.app>`
- Card de contexto/branding: `.brand-hero-card.public-auth-hero`
- Card de formulario: `.surface-card.public-form-card`
- Divisor visual: `.public-divider`
- Pontos de apoio: `.micro-surface.public-point` + `.public-icon-wrap`

Classes de home publica:
- `.public-home`, `.public-home-hero`, `.public-home-aside`, `.public-feature-grid`, `.public-kpi`, `.public-step-chip`, `.public-pulse-dot`

## Dashboard (classes CSS puro residual)
Classes que permanecem em CSS puro (ver seção "CSS Puro Residual"):
- `.ds-pill-btn`: botões de chip/preset — hover com `color-mix()`
- `.ds-inline-btn`: ação inline padrão — hover com `color-mix()`
- `.ds-inline-btn-danger`: ação inline destrutiva — hover com `color-mix()`
- `.ds-empty-state`: estado vazio padronizado
- `.panel-collapsible`: container colapsável com transição data-driven

Classes migradas para Tailwind inline (não existem mais em `app.css`):
- `.dashboard-layout-grid` → `grid gap-4 lg:gap-6 [grid-template-areas:...]`
- `.dashboard-header-area` → `[grid-area:header] flex flex-col gap-3`
- `.bulk-hero-area` / `.operations-area` / `.analytics-area` → `[grid-area:nome]`
- `.ds-edit-form` (base) → `border border-base-content/16 bg-base-100/80`

## Bulk import (migrado para Tailwind inline)
Todas as classes de bulk import foram migradas para utilitários Tailwind inline nos templates. Não existem mais em `app.css`, exceto:
- `.bulk-import-hero` + `::before`: gradientes radiais + `box-shadow` múltiplo + pseudo-elemento (CSS puro)
- `.bulk-studio-shell`: gradientes radiais + `color-mix()` (CSS puro)
- `.ds-edit-form.loading::after`: pseudo-elemento de loading (CSS puro)

## Analytics (migrado para Tailwind inline)
Todas as classes de analytics foram migradas para utilitários Tailwind inline nos templates. Não existem mais em `app.css`.

## Componentes Base Phoenix
Refinados em `lib/organizer_web/components/core_components.ex`:
- Flash com superfície e sombra consistentes
- Botão com variantes `primary | soft | outline`
- Inputs e labels alinhados ao sistema
- Tabela/lista com superfícies dark e hover consistente

## Abordagem de Estilização (pós-migração Tailwind)

O projeto concluiu a migração para **Tailwind CSS v4 com utilitários inline nos templates HEEx**. A camada de classes semânticas customizadas foi eliminada em favor de utilitários Tailwind aplicados diretamente nos atributos `class` dos elementos.

### Princípios

- **Utilitários inline**: todo estilo de layout, tipografia, espaçamento e cor é expresso com classes Tailwind diretamente no `class` do elemento HEEx — sem `@apply`, sem classes semânticas locais.
- **Valores arbitrários**: use a sintaxe `[valor]` do Tailwind para valores fora da escala padrão: `text-[0.72rem]`, `bg-base-100/88`, `min-h-[15rem]`.
- **CSS puro residual**: apenas as categorias listadas na seção "CSS Puro Residual" abaixo permanecem em `assets/css/app.css`.
- **Nunca usar `@apply`**: proibido pelo projeto — escreva os utilitários diretamente no template.

### Sintaxe HEEx para classes condicionais

Use sempre a sintaxe de lista para múltiplas classes ou classes condicionais:

```heex
<%!-- Condição booleana simples --%>
<div class={["base-classes", @condition && "conditional-class"]}>

<%!-- Condição com dois ramos --%>
<div class={["base-classes", if(@condition, do: "true-class", else: "false-class")]}>

<%!-- Exemplo real: dot de progresso ativo/inativo --%>
<span class={[
  "w-2 h-2 rounded-full transition-all duration-200",
  if(@active, do: "w-6 bg-gradient-to-r from-cyan-400 to-emerald-400 shadow-[0_0_12px_rgba(34,211,238,0.6)]", else: "bg-base-content/30")
]}></span>
```

## CSS Puro Residual

As seguintes classes **permanecem em `assets/css/app.css`** e não devem ser migradas para Tailwind inline. Cada categoria tem uma justificativa técnica.

### color-mix() — sem equivalente Tailwind direto

Tailwind não suporta `color-mix()` com variáveis CSS do daisyUI nativamente. Essas classes ficam em CSS puro até que o suporte seja adicionado:

| Classe | Uso |
|--------|-----|
| `.surface-card` | Cartão padrão — borda, background e sombra com `color-mix()` |
| `.micro-surface` | Cartão secundário — borda e background com `color-mix()` |
| `.brand-hero-card` | Hero/boas-vindas — gradientes radiais + `color-mix()` |
| `.ds-pill-btn` | Botão chip/preset — hover states com `color-mix()` |
| `.ds-inline-btn` | Ação inline padrão — hover states com `color-mix()` |
| `.ds-inline-btn-danger` | Ação inline destrutiva — hover states com `color-mix()` |
| `.identity-pill` | Chip de identidade do usuário — borda, background e cor com `color-mix()` |
| `.top-nav-link` | Links de navegação — hover e focus com `color-mix()` |
| `.public-*` | Classes da área pública (home, auth) — hover states e bordas com `color-mix()` |

### Pseudo-elementos — não replicáveis inline

Pseudo-elementos (`::before`, `::after`) não têm equivalente em atributos `class` do HTML:

| Classe | Pseudo-elemento | Descrição |
|--------|----------------|-----------|
| `.skeleton-bar::after` | `::after` | Shimmer animado sobre as barras do skeleton |
| `.ds-edit-form.loading::after` | `::after` | Overlay de loading no formulário de edição inline |
| `.bulk-import-hero::before` | `::before` | Gradiente radial de fundo do hero de importação |
| `.brand-hero-card::after` | `::after` | Efeito de profundidade do card hero |
| `.public-*::before` | `::before` | Pseudo-elementos decorativos das páginas públicas |

### Animações e transições data-driven

Classes que dependem de `@keyframes` customizados ou de transições acionadas por atributos `data-*`:

| Classe | Motivo |
|--------|--------|
| `.onboarding-spotlight` | `box-shadow: 0 0 0 9999px` trick + animação `pulse-spotlight` |
| `.panel-collapsible` | Transição `max-height`/`opacity` acionada por `data-collapsed` |
| `.panel-accordion-header` | Layout e transições do accordion mobile |
| `.panel-accordion-content` | Transição `max-height` acionada por `data-expanded` |
| `.onboarding-arrow-down` / `.onboarding-arrow-right` | Animações `arrow-pulse-down` / `arrow-pulse-right` |

### SVG styling com !important

| Classe | Motivo |
|--------|--------|
| `.contex-plot` e filhos | Estilização de SVG gerado pela lib `contex` — usa `!important` para sobrescrever estilos inline do SVG; sem equivalente Tailwind |

## Regras de uso
- Sempre preferir utilitários Tailwind inline antes de criar classes CSS locais.
- Evitar hardcode de cores (`text-slate-*`, `bg-white`) fora de contexto visual específico.
- Para novas telas:
  1. Estrutura com `.surface-card` ou `.brand-hero-card` (permanecem em CSS puro)
  2. Layout e espaçamento com utilitários Tailwind inline (`grid`, `flex`, `gap-*`, `p-*`)
  3. Ações com `.btn-primary` e fallback `.btn-soft`
  4. Campos com `<.input>` do CoreComponents
  5. Estados vazios com `.ds-empty-state`
  6. Classes condicionais com sintaxe de lista HEEx (ver seção acima)

## Assets de marca
- Logo: `priv/static/images/organizer-logo.svg`
- Favicon: `priv/static/favicon.svg`

## Observacao
A plataforma usa dark mode fixo. Nao existe alternancia light/dark.

daisyUI e carregado como plugin Tailwind vendorizado (`assets/vendor/daisyui.js` e `assets/vendor/daisyui-theme.js`), nao como dependencia hex. O tema customizado e definido diretamente em `app.css` via `@plugin "../vendor/daisyui-theme"`. Nao adicione daisyUI como dependencia hex.

## Dashboard Layout (Tailwind inline)

O layout do dashboard usa utilitários Tailwind com CSS Grid areas nomeadas, aplicados diretamente no template `dashboard_live.ex`:

```heex
<div
  id="dashboard-keyboard-shortcuts"
  class="grid gap-4 lg:gap-6 [grid-template-areas:'header'_'bulk-hero'_'operations'_'analytics'] lg:grid-cols-2 lg:[grid-template-areas:'header_header'_'bulk-hero_bulk-hero'_'operations_analytics']"
  data-layout-mode={@panel_layout_mode}
>
  <div class="[grid-area:header] flex flex-col gap-3">
    <DashboardHeader.dashboard_header ... />
    <ActionStrip.action_strip ... />
  </div>

  <div class="[grid-area:bulk-hero]">
    <BulkImportHero.bulk_import_hero ... />
  </div>

  <div class="[grid-area:operations] panel-collapsible" ...>
    <OperationsPanel.operations_panel ... />
  </div>

  <div class="[grid-area:analytics] panel-collapsible" ...>
    <AnalyticsPanel.analytics_panel ... />
  </div>
</div>
```

O `gap-3` no wrapper `[grid-area:header]` garante espaçamento consistente entre `DashboardHeader` e `ActionStrip`.

### Componentes com CSS puro residual no dashboard

- `.panel-collapsible`: transição `max-height`/`opacity` acionada por `data-collapsed` (CSS puro)
- `.panel-accordion-header` / `.panel-accordion-content`: accordion mobile com transições data-driven (CSS puro)
- `.bulk-import-hero`: gradientes radiais + `box-shadow` múltiplo + pseudo-elemento `::before` (CSS puro)
- `.onboarding-spotlight`: `box-shadow: 0 0 0 9999px` trick + animação `pulse-spotlight` (CSS puro)

### Accessibility Classes

- `.keyboard-nav-active`: ativa estilos de foco aprimorados (outline 3px solid info + box-shadow)
- `.skip-link`: link de pulo para navegação por teclado (z-index: 10000)

### Animações em `@keyframes` (app.css)

Todos os `@keyframes` permanecem em `app.css` — não têm equivalente Tailwind:

- `fade-in`: fade in simples (300ms)
- `slide-up`: slide up com fade (400ms cubic-bezier)
- `pulse-spotlight`: pulsação do spotlight (2s infinite)
- `pulse-skeleton`: pulsação do skeleton loader (1.5s infinite)
- `shimmer-skeleton`: shimmer effect para skeleton (2s infinite)
- `shimmer`: shimmer do `ds-edit-form.loading::after`
- `hint-fade-in`, `arrow-pulse-down`, `arrow-pulse-right`: animações do onboarding
- `highlight-pulse`, `dropdown-fade-in`, `public-float`, `public-stagger-in`, `public-pulse`

Todas as animações respeitam `prefers-reduced-motion` quando aplicável.
