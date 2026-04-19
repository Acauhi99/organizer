# Organizer

Aplicação de organização pessoal construída com **Elixir + Phoenix 1.8 + LiveView**, com persistência em SQLite e autenticação multiusuário.

## Objetivo

Centralizar tarefas, metas e finanças em um painel operacional único, com fluxo rápido de captura, análise e colaboração entre contas.

## Stack

- Elixir `~> 1.15`
- Phoenix `~> 1.8.1`
- Phoenix LiveView `~> 1.1`
- Ecto + SQLite (`ecto_sqlite3`)
- Tailwind CSS v4 + daisyUI vendorizado
- Req para integração HTTP

## Início rápido

```bash
mix setup
mix phx.server
```

Aplicação disponível em `http://localhost:4000`.

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
