#!/usr/bin/env sh
set -eu

if command -v apk >/dev/null 2>&1; then
	apk add --no-cache build-base git nodejs npm sqlite-dev >/dev/null
elif command -v apt-get >/dev/null 2>&1; then
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -y >/dev/null
	apt-get install -y --no-install-recommends build-essential git nodejs npm libsqlite3-dev >/dev/null
	rm -rf /var/lib/apt/lists/*
fi

mix local.hex --force
mix local.rebar --force
mix deps.get
mix "$@"
