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
