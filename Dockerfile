FROM elixir:1.17

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential git nodejs npm libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile && mix assets.deploy

EXPOSE 4000

CMD ["sh", "-c", "mix ecto.migrate --no-compile && mix phx.server --no-compile"]
