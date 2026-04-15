#!/usr/bin/env sh
set -eu

echo "[test_unit] Legacy path detected; redirecting to scripts/tests/domain_suite.sh"
exec sh scripts/tests/domain_suite.sh "$@"
