.PHONY: help precommit check-format \
        test-domain test-web test-all \
        test-e2e \
        test-unit test-stage2 \
        test-domain-local test-web-local test-local-all \
        db-create db-migrate db-reset run setup

# ── defaults ────────────────────────────────────────────────────────────────

help:
	@echo ""
	@echo "Targets disponíveis:"
	@echo ""
	@echo "  make precommit          # Formata, compila (erros=fatal), testa (alias mix precommit)"
	@echo "  make check-format       # Verifica formatação sem alterar arquivos (igual ao CI)"
	@echo ""
	@echo "  make setup              # Instala deps e configura banco"
	@echo "  make run                # Aplica migrations e sobe o servidor"
	@echo ""
	@echo "  make test-domain        # Suite de domínio via Docker"
	@echo "  make test-web           # Suite web via Docker"
	@echo "  make test-all           # Domain + web via Docker"
	@echo "  make test-e2e           # Suite E2E Playwright"
	@echo ""
	@echo "  make test-domain-local  # Suite de domínio sem Docker"
	@echo "  make test-web-local     # Suite web sem Docker"
	@echo "  make test-local-all     # Domain + web sem Docker"
	@echo ""
	@echo "  make db-create          # Cria banco de desenvolvimento"
	@echo "  make db-migrate         # Aplica migrations pendentes"
	@echo "  make db-reset           # Recria banco e reaplica migrations"
	@echo ""

# ── qualidade ───────────────────────────────────────────────────────────────

# Espelho exato do alias `mix precommit` — formata arquivos, compila e testa.
# Use antes de fazer push para garantir que o CI vai passar.
precommit:
	mix precommit

# Mesma verificação de formatação que o CI executa (não altera arquivos).
# Use para diagnosticar falhas de format sem modificar nada.
check-format:
	mix format --check-formatted

# ── testes ──────────────────────────────────────────────────────────────────

test-domain:
	sh scripts/tests/domain_suite.sh

test-web:
	sh scripts/tests/web_suite.sh

test-all: test-domain test-web

test-e2e:
	cd e2e && npm install && npm run install:browsers && npm test

# aliases legados
test-unit: test-domain
test-stage2: test-web

test-domain-local:
	MIX_ENV=test mix test \
	  test/organizer/accounts_test.exs \
	  test/organizer/planning/amount_parser_test.exs \
	  test/organizer/planning/amount_parser_property_test.exs

test-web-local:
	MIX_ENV=test mix test \
	  test/organizer_web/live/auth_flow_live_test.exs \
	  test/organizer_web/controllers/api/v1/finance_entry_controller_test.exs \
	  test/organizer_web/controllers/api/v1/fixed_cost_controller_test.exs \
	  test/organizer_web/controllers/api/v1/important_date_controller_test.exs

test-local-all: test-domain-local test-web-local

# ── banco ────────────────────────────────────────────────────────────────────

setup:
	mix setup

db-create:
	mix ecto.create

db-migrate:
	mix compile --no-warnings
	mix ecto.migrate --no-compile

db-reset:
	mix compile --no-warnings
	mix ecto.drop --no-compile
	mix ecto.create --no-compile
	mix ecto.migrate --no-compile

# ── servidor ─────────────────────────────────────────────────────────────────

run: db-migrate
	mix phx.server --no-compile
