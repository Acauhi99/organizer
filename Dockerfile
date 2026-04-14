FROM elixir:1.17

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential git nodejs npm libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get

COPY . .

EXPOSE 4000
ENV MIX_ENV=dev

CMD ["mix", "phx.server"]
