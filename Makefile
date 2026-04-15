.PHONY: help test-domain test-web test-all test-unit test-stage2 test-domain-local test-web-local test-local-all db-create db-migrate db-reset run

help:
	@echo "Targets disponiveis:"
	@echo "  make test-domain      # Suite de dominio via Docker"
	@echo "  make test-web         # Suite web focada via Docker"
	@echo "  make test-all         # Domain + web via Docker"
	@echo "  make test-unit        # Alias legado para test-domain"
	@echo "  make test-stage2      # Alias legado para test-web"
	@echo "  make test-domain-local # Suite de dominio sem Docker"
	@echo "  make test-web-local    # Suite web sem Docker"
	@echo "  make test-local-all    # Domain + web sem Docker"
	@echo "  make db-create         # Cria banco de desenvolvimento"
	@echo "  make db-migrate        # Aplica migrations pendentes"
	@echo "  make db-reset          # Recria banco e reaplica migrations"
	@echo "  make run               # Sobe app local com migration aplicada"

test-domain:
	sh scripts/tests/domain_suite.sh

test-web:
	sh scripts/tests/web_suite.sh

test-all: test-domain test-web

test-unit: test-domain

test-stage2: test-web

test-domain-local:
	MIX_ENV=test mix test test/organizer/accounts_test.exs test/organizer/planning_test.exs test/organizer/planning/analytics_test.exs

test-web-local:
	MIX_ENV=test mix test test/organizer_web/live/dashboard_live_test.exs test/organizer_web/live/auth_flow_live_test.exs test/organizer_web/controllers/api/v1/task_controller_test.exs test/organizer_web/controllers/api/v1/finance_entry_controller_test.exs test/organizer_web/controllers/api/v1/goal_controller_test.exs test/organizer_web/controllers/api/v1/fixed_cost_controller_test.exs test/organizer_web/controllers/api/v1/important_date_controller_test.exs

test-local-all: test-domain-local test-web-local

db-create:
	mix ecto.create

db-migrate:
	mix ecto.migrate

db-reset:
	mix ecto.drop
	mix ecto.create
	mix ecto.migrate

run: db-migrate
	mix phx.server
