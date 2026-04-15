#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"

HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

TEST_IMAGE="${TEST_IMAGE:-organizer-app:latest}"
if ! docker image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
  TEST_IMAGE="elixir:1.17"
fi

TEST_FILES="test/organizer_web/controllers/api/v1/task_controller_test.exs \
test/organizer_web/controllers/api/v1/finance_entry_controller_test.exs \
test/organizer_web/controllers/api/v1/goal_controller_test.exs \
test/organizer_web/controllers/api/v1/fixed_cost_controller_test.exs \
test/organizer_web/controllers/api/v1/important_date_controller_test.exs \
test/organizer_web/live/dashboard_live_test.exs \
test/organizer_web/live/auth_flow_live_test.exs"

echo "[web-tests] Running focused web suite in Docker image: $TEST_IMAGE"
echo "[web-tests] Cleaning test build artifacts (_build/test and organizer_test.db*)"

status=0

docker run --rm \
  -v "$PWD":/app \
  alpine:3.20 \
  sh -lc "rm -rf /app/_build/test /app/organizer_test.db /app/organizer_test.db-shm /app/organizer_test.db-wal"

docker run --rm \
  -e MIX_ENV=test \
  -v "$PWD":/app \
  -w /app \
  "$TEST_IMAGE" \
  sh -lc "sh scripts/docker/run_mix.sh test $TEST_FILES > /tmp/web-tests.log 2>&1; run_status=\$?; tail -n 80 /tmp/web-tests.log; echo WEB_EXIT:\$run_status; exit \$run_status" || status=$?

docker run --rm \
  -v "$PWD":/app \
  alpine:3.20 \
  sh -lc "chown -R $HOST_UID:$HOST_GID /app/_build /app/organizer_test.db /app/organizer_test.db-shm /app/organizer_test.db-wal 2>/dev/null || true"

exit "$status"
