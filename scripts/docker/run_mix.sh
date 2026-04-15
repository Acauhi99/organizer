#!/usr/bin/env sh
set -eu

MIX_TASK="${1:-help}"

needs_node_tools() {
	case "$MIX_TASK" in
	assets.setup|assets.build|assets.deploy|phx.server)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

needs_bootstrap=false

for cmd in gcc git; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		needs_bootstrap=true
	fi
done

if [ ! -f /usr/include/sqlite3.h ]; then
	needs_bootstrap=true
fi

if needs_node_tools; then
	for cmd in node npm; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			needs_bootstrap=true
		fi
	done
fi

if [ "$needs_bootstrap" = true ]; then
	echo "[docker_mix] Installing missing system dependencies for task: $MIX_TASK"

	if command -v apk >/dev/null 2>&1; then
		apk_packages="build-base git sqlite-dev"
		if needs_node_tools; then
			apk_packages="$apk_packages nodejs npm"
		fi
		apk add --no-cache $apk_packages
	elif command -v apt-get >/dev/null 2>&1; then
		export DEBIAN_FRONTEND=noninteractive
		apt_packages="build-essential git libsqlite3-dev"
		if needs_node_tools; then
			apt_packages="$apt_packages nodejs npm"
		fi
		apt-get update -y
		apt-get install -y --no-install-recommends $apt_packages
		rm -rf /var/lib/apt/lists/*
	fi
else
	echo "[docker_mix] System dependencies already satisfied for task: $MIX_TASK"
fi

if [ "$MIX_TASK" = "test" ] && [ -d deps ] && [ "$(ls -A deps 2>/dev/null)" ]; then
	echo "[docker_mix] Using vendored deps for test run; skipping Hex bootstrap and deps.get"
	mix "$@"
	exit 0
fi

echo "[docker_mix] Ensuring Hex and Rebar"
mix local.hex --force
mix local.rebar --force

echo "[docker_mix] Fetching mix dependencies"
mix deps.get

mix "$@"
