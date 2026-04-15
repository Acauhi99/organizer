#!/usr/bin/env sh
set -eu

echo "[docker_mix] Legacy path detected; redirecting to scripts/docker/run_mix.sh"
exec sh scripts/docker/run_mix.sh "$@"
