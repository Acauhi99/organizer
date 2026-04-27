# Testes, Qualidade e Validação Pré-commit

## Estratégia de testes na codebase

## 1) Domínio (`test/organizer/**`)

Foco em regras de negócio, validações e invariantes.

- tests unitários de contexts e módulos de parsing
- property-based tests com `stream_data` para casos extremos

## 2) Web (`test/organizer_web/**`)

Foco em comportamento observável da interface e API.

- LiveView tests com `Phoenix.LiveViewTest`
- controller/API tests para contratos HTTP
- component tests para rendering de componentes críticos

## 3) E2E browser (`e2e/**`)

Foco em regressão retroativa dos fluxos completos com browser real:

- público/autenticação (home, cadastro, login/logout, erro de credencial)
- módulos autenticados (`/finances`, `/account-links`, `/users/settings`)
- colaboração financeira (`/account-links`, convite, aceite com retomada pós-login, compartilhado, acerto, desativação)
- experiência transversal (onboarding e atalhos globais)
- smoke da API autenticada (`/api/v1/*`) via sessão real do browser

Referências oficiais:

- ExUnit: https://hexdocs.pm/ex_unit/ExUnit.html
- Phoenix testing: https://hexdocs.pm/phoenix/testing.html
- LiveView testing: https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html

## Boas práticas de assertions

- Preferir estrutura/estado a copy textual frágil.
- Em LiveView, usar `has_element?/2`, `element/2`, `render_click`, `render_submit`, `render_change`.
- Garantir IDs estáveis em elementos importantes para seleção nos testes.

## Comandos de validação local

Validação rápida por área:

```bash
mix test test/organizer_web/controllers/api/v1/finance_entry_controller_test.exs
mix test test/organizer/shared_finance/shared_entries_test.exs
```

Validação completa recomendada antes de commit:

```bash
mix precommit
```

Validação E2E completa:

```bash
cd e2e
npm install
npm run install:browsers
npm test
```

`mix precommit` neste projeto executa:

1. compilação com warnings como erro
2. limpeza de deps não usadas
3. formatação
4. suíte de testes

Aliases úteis:

```bash
make precommit
make test-domain
make test-web
make test-all
```

## Política de merge local

Não considerar uma mudança pronta sem:

1. testes relevantes do escopo alterado
2. `mix precommit` verde
3. atualização de docs em `docs/` quando comportamento/arquitetura mudar

## Doctests (opcional para novos módulos públicos)

Quando o módulo tiver API pública reutilizável, prefira incluir exemplos em `@doc` e habilitar doctest para evitar drift de documentação.

Referência oficial:

- https://hexdocs.pm/ex_unit/ExUnit.DocTest.html
