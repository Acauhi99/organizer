# Organizer

Aplicação de organização financeira em **Elixir + Phoenix 1.8 + LiveView**, com SQLite e autenticação multiusuário.

## Objetivo

Unificar operação financeira pessoal + compartilhada em fluxos rápidos (`/finances` e `/account-links`), com colaboração por convite e fechamento no fluxo unificado de vínculo (`/account-links/:link_id`).

## Stack

- Elixir `~> 1.15`
- Phoenix `~> 1.8.1`
- Phoenix LiveView `~> 1.1`
- Ecto + SQLite (`ecto_sqlite3`)
- Tailwind CSS v4 + daisyUI vendorizado (tema custom `organizer_neon_grid`)
- Flop + Flop.Phoenix para paginação/filtros
- Phoenix Storybook (dev)
- Req para integração HTTP

## Início rápido

```bash
mix setup
mix phx.server
```

Aplicação: `http://localhost:4000`.

## Validação atual

Suíte `test/**` removida temporariamente durante refactor visual. Validação vigente:

```bash
mix format
mix compile --warnings-as-errors
mix xref graph --format plain --label compile-connected --fail-above 0
```

Também manter revisão visual dos fluxos críticos no browser.

## E2E (Playwright)

```bash
cd e2e
npm install
npm run install:browsers
npm test
```

## Documentação

Tudo em [`/docs`](docs/README.md).

Leituras de entrada:

- [Visão geral docs](docs/README.md)
- [Arquitetura](docs/architecture.md)
- [Features](docs/features.md)
- [Design system](docs/design-system.md)
- [Guia AI](docs/development/ai-playbook.md)
