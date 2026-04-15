# Organizer

Organizador financeiro e de tarefas com Phoenix LiveView, SQLite e autenticacao multiusuario.

## Funcionalidades iniciais

- Auth com `phx.gen.auth` (registro, login, sessao e configuracoes de usuario)
- Dashboard LiveView em `/dashboard` com quick add para:
	- tarefas
	- lancamentos financeiros
	- metas
- API REST inicial em `/api/v1/tasks`
- Isolamento por usuario em todas as consultas da camada de dominio (`Scope` + `user_id`)
- Modelo de dominio inicial para:
	- `tasks`
	- `finance_entries`
	- `fixed_costs`
	- `important_dates`
	- `goals`

## Rodando local (sem Docker)

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Rodando com Docker

```bash
docker compose up --build
```

Aplicacao em `http://localhost:4000`.

### Executando testes com Make

```bash
make test-domain
make test-web
make test-all
make run
```

Aliases de compatibilidade:

```bash
make test-unit
make test-stage2
```

Versao sem Docker (usa Mix local):

```bash
make test-domain-local
make test-web-local
make test-local-all
```

Banco local (dev):

```bash
make db-create
make db-migrate
make db-reset
```

### Suite unit-first (Docker)

```bash
sh scripts/tests/domain_suite.sh
```

Foco em regras de dominio (sem testes de integracao web). O script imprime o tail e finaliza com `DOMAIN_EXIT:<code>`.
Por padrao o script usa a imagem local `organizer-app:latest` (com Hex preinstalado) e faz fallback para `elixir:1.17` se ela nao existir.

Atalho legado mantido: `sh scripts/test_unit.sh`.

### Suite focada da Etapa 2 (Docker)

```bash
sh scripts/tests/web_suite.sh
```

O script imprime o tail dos testes e finaliza com `WEB_EXIT:<code>` para facilitar validacao rapida.

Atalho legado mantido: `sh scripts/test_stage2.sh`.

## Deploy Fly.io (base)

1. Crie app e volume:

```bash
fly launch --no-deploy
fly volumes create organizer_data --region gru --size 3
```

2. Configure secrets:

```bash
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
```

3. Deploy:

```bash
fly deploy
```

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
