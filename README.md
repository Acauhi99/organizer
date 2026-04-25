# Organizer

Aplicação de organização pessoal construída com **Elixir + Phoenix 1.8 + LiveView**, com persistência em SQLite e autenticação multiusuário.

## Objetivo

Centralizar tarefas e finanças em fluxos operacionais rápidos (`/tasks` e `/finances`), com análise contínua e colaboração entre contas por convite.

## Stack

- Elixir `~> 1.15`
- Phoenix `~> 1.8.1`
- Phoenix LiveView `~> 1.1`
- Ecto + SQLite (`ecto_sqlite3`)
- Tailwind CSS v4 + daisyUI vendorizado (tema custom)
- Req para integração HTTP

## Início rápido

```bash
mix setup
mix phx.server
```

Aplicação disponível em `http://localhost:4000`.

## Testes E2E (Playwright)

```bash
cd e2e
npm install
npm run install:browsers
npm test
```

Observações:

- A suíte E2E sobe o Phoenix automaticamente na porta `4010`.
- Para reaproveitar um servidor já em execução, use `PLAYWRIGHT_BASE_URL`, por exemplo:
  `PLAYWRIGHT_BASE_URL=http://127.0.0.1:4000 npm test`.

## Documentação

Toda documentação de produto e engenharia está em [`/docs`](docs/README.md).

Leituras recomendadas para começar:

- [Visão geral da documentação](docs/README.md)
- [Arquitetura](docs/architecture.md)
- [Features](docs/features.md)
- [Guia para desenvolvimento por IA](docs/development/ai-playbook.md)
- [Testes e validação pré-commit](docs/development/testing-and-quality.md)

## Estrutura de documentação

- `README.md` na raiz: visão rápida e links de entrada.
- `docs/`: documentação detalhada de arquitetura, padrões de desenvolvimento, testes, UX e roadmap.

Observação: `AGENTS.md` permanece na raiz por ser arquivo operacional de instruções para agentes.
