# Design System

## Direção visual (ativa)

- Tema padrão: **Neon Grid** (dark mode default).
- Base de contraste alto para leitura contínua.
- Acentos: ciano + lime para ação/estado.
- Hierarquia forte com superfícies escuras em camadas.

## Tokens principais

- Theme: `organizer_neon_grid`
- `--color-base-100/200/300`: superfícies dark
- `--color-base-content`: texto de alto contraste
- `--color-primary`: cyan
- `--color-secondary`: lime
- Motion tokens:
  - `--motion-fast: 140ms`
  - `--motion-normal: 220ms`
  - `--motion-slow: 320ms`
  - `--ease-neon: cubic-bezier(0.22, 1, 0.36, 1)`

## Stack e regras

- Tailwind CSS v4 inline nos templates HEEx (padrão).
- daisyUI vendorizado para tokens/tema base.
- CSS residual em `assets/css/app.css` apenas para:
  - tokens globais
  - gradientes complexos de background
  - keyframes utilitários
  - utilitários transversais não práticos em classe inline

## Regras obrigatórias

1. Priorizar classes Tailwind diretamente no template.
2. Não usar `@apply`.
3. Evitar classes semânticas novas por tela sem ganho real.
4. Garantir contraste legível em todos os estados (`normal`, `hover`, `focus`, `disabled`).
5. Respeitar `prefers-reduced-motion`.

## Motion e microinterações

- Hover com deslocamento curto (`translate-y` leve).
- Entradas suaves (`fade/slide`) com duração curta.
- Feedback de foco visível sempre presente.
- Sem animação excessiva que reduza legibilidade.

## Acessibilidade visual

- Foco por teclado nítido.
- Tipografia legível em densidade alta de informação.
- Superfícies com contraste consistente em telas pequenas e grandes.
