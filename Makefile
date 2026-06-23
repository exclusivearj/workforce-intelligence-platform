.PHONY: help infra-up infra-down infra-reset \
        ingestion-setup ingestion-test ingestion-dbt \
        llm-eval-setup llm-eval-test \
        governance-setup governance-test \
        dashboard-run dashboard-test \
        test-all lint-all

help:
	@echo ""
	@echo "workforce-intelligence-platform — top-level targets"
	@echo "──────────────────────────────────────────────────────"
	@echo "  make infra-up          Start Postgres + Trino + Airflow"
	@echo "  make infra-down        Stop all infra containers"
	@echo "  make infra-reset       Tear down + wipe volumes (destructive)"
	@echo ""
	@echo "  make ingestion-setup   Init schemas, roles, seed synthetic data"
	@echo "  make ingestion-dbt     Run dbt models in ingestion/"
	@echo "  make ingestion-test    Run ingestion test suite"
	@echo ""
	@echo "  make llm-eval-setup    Install pgvector, seed Q&A dataset, embed"
	@echo "  make llm-eval-test     Run llm-eval test suite"
	@echo ""
	@echo "  make governance-setup  Apply classification DDL + audit triggers"
	@echo "  make governance-test   Run governance test suite"
	@echo ""
	@echo "  make dashboard-run     Launch Streamlit app on :8501"
	@echo "  make dashboard-test    Run dashboard test suite"
	@echo ""
	@echo "  make test-all          Run all four test suites"
	@echo "  make lint-all          Ruff + sqlfluff across all modules"
	@echo ""

# ── Shared infrastructure ──────────────────────────────────────
infra-up:
	docker compose up -d postgres trino mock-hr airflow-init airflow-webserver airflow-scheduler
	@echo "Waiting for Postgres to be ready..."
	@until docker compose exec postgres pg_isready -U postgres > /dev/null 2>&1; do sleep 1; done
	@echo "Infrastructure up. Airflow UI: http://localhost:8081"

infra-down:
	docker compose down

infra-reset:
	docker compose down -v
	@echo "Volumes wiped."

# ── Ingestion ──────────────────────────────────────────────────
ingestion-setup:
	$(MAKE) -C 1-ingestion setup

ingestion-dbt:
	$(MAKE) -C 1-ingestion dbt-run

ingestion-test:
	$(MAKE) -C 1-ingestion test

# ── LLM Eval ──────────────────────────────────────────────────
llm-eval-setup:
	$(MAKE) -C 2-llm-eval setup

llm-eval-test:
	$(MAKE) -C 2-llm-eval test

# ── Governance ────────────────────────────────────────────────
governance-setup:
	$(MAKE) -C 3-governance setup

governance-test:
	$(MAKE) -C 3-governance test

# ── Dashboard ─────────────────────────────────────────────────
dashboard-run:
	$(MAKE) -C 4-dashboard run

dashboard-test:
	$(MAKE) -C 4-dashboard test

# ── Cross-cutting ─────────────────────────────────────────────
test-all: ingestion-test llm-eval-test governance-test dashboard-test
	@echo "All test suites passed."

lint-all:
	ruff check 1-ingestion/src 2-llm-eval/src 3-governance/src 4-dashboard/src
	cd 1-ingestion && sqlfluff lint dbt/models --dialect postgres
	@echo "Lint complete."
