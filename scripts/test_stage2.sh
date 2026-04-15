#!/usr/bin/env sh
set -eu

echo "[test_stage2] Legacy path detected; redirecting to scripts/tests/web_suite.sh"
exec sh scripts/tests/web_suite.sh "$@"
