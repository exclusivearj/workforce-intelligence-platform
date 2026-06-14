# TASKS.md — workforce-intelligence-platform

> Instructions for Claude (or a developer) implementing this monorepo.
> Read this file first. Then read each project's own TASKS.md before touching any code.

---

## Purpose

This monorepo is a portfolio project targeting Airbnb's Senior Data Engineer, People Analytics role.
It demonstrates four capabilities the JD explicitly requires:

| Module | JD requirement addressed |
|---|---|
| `ingestion/` | Python API ingestion · Postgres admin · Trino/Presto SQL · dbt |
| `llm-eval/` | LLM-backed data pipelines · eval datasets · feedback loops · PII-safe AI |
| `governance/` | Sensitivity classification · access controls · audit logging |
| `dashboard/` | Streamlit data products · non-technical stakeholder UX |

Airflow is the orchestration spine across all four modules. Each module has its own
DAG group. A single `ExternalTaskSensor` in `llm-eval` waits on the ingestion DAG,
and `governance` sensors wait on ingestion before applying DDL. `dashboard` is
triggered independently on a daily schedule.

---

## Implementation rules (read before writing any code)

1. **Python version**: 3.11 throughout. Use `pyproject.toml` (not `setup.py`) for all packages.
2. **Postgres image**: `pgvector/pgvector:pg16` — this gives pgvector out of the box.
3. **Trino version**: 438. Use the Trino Python client (`trino` PyPI package).
4. **Airflow version**: 2.9.1. Use `TaskFlow API` (`@task` decorator) for all Python operators.
5. **dbt version**: dbt-core 1.8.x with dbt-postgres adapter.
6. **Formatting**: `ruff` for Python (line length 100). `sqlfluff` for SQL (dialect: trino for analytical, postgres for DDL).
7. **Testing**: `pytest` with `pytest-cov`. Minimum 80% coverage on all `src/` modules.
8. **Secrets**: Never hardcode. Always read from environment variables. Use `python-dotenv` for local dev.
9. **Synthetic data**: Use `faker` (v25+) for all employee/HR data generation. Never use real personal data.
10. **Docker**: Every project must be runnable with `docker compose up` from the repo root.

---

## Build sequence

Projects must be built in this exact order due to shared infrastructure dependencies:

```
Phase 0 (root)     Shared infra — docker-compose.yml, .env, root Makefile
Phase 1            ingestion/   — Postgres schemas + Trino catalog established here
Phase 2            llm-eval/    — adds pgvector extension to existing Postgres instance
Phase 3            governance/  — adds audit tables + masking views on top of ingestion schemas
Phase 4            dashboard/   — reads from Trino; all upstream data must exist
Phase 5            linkedin-articles/ — written last, after all projects work end-to-end
```

---

## Phase 0 — Shared infrastructure

### Files to implement

**`docker-compose.yml`** (already scaffolded)
- Services: `postgres` (pgvector/pgvector:pg16), `trino` (trinodb/trino:438), `airflow-init`, `airflow-webserver`, `airflow-scheduler`
- Postgres healthcheck must pass before any other service starts
- Mount all four projects' DAG directories into Airflow

**`.env.example`** (already scaffolded)
- Document every environment variable with a comment
- All secrets default to placeholder strings that fail loudly, not silently

**Root `Makefile`** (already scaffolded)
- `make infra-up` — starts shared infra, waits for Postgres healthcheck
- `make test-all` — delegates to each module's `make test`
- `make lint-all` — ruff + sqlfluff across all modules

### Acceptance criteria
- [ ] `docker compose up -d` starts without errors
- [ ] `make infra-up` completes and Airflow UI is reachable at http://localhost:8081
- [ ] Postgres is accessible on port 5432

---

## Phase 1 — ingestion/

**See `ingestion/TASKS.md` for full implementation details.**

### Summary
Build three Python source connectors, land data into Postgres staging, transform with dbt,
expose Trino OLAP queries. This phase establishes the shared data layer all other projects use.

### Cross-module contracts this phase must deliver
- Postgres schemas: `raw`, `staging`, `analytics` — must exist before governance or dashboard run
- Postgres roles: `ingestion_writer`, `dbt_transformer`, `analyst_reader` — used by all modules
- Trino catalog `postgresql` pointing at the workforce database
- dbt models: `analytics.dim_employees`, `analytics.fct_headcount_daily`, `analytics.fct_attrition_monthly`, `analytics.rpt_recruiting_funnel`

### Airflow DAG group: `hr_ingestion`
- Schedule: `0 6 * * *` (daily 6am)
- Tasks: `extract_workday` → `extract_greenhouse` → `extract_airtable` → `detect_schema_drift` → `run_dbt_models` → `alert_on_pii_change`
- On success: trigger `llm_eval_embedding_refresh` via `TriggerDagRunOperator`

---

## Phase 2 — llm-eval/

**See `llm-eval/TASKS.md` for full implementation details.**

### Summary
Install pgvector on the shared Postgres instance, generate synthetic HR Q&A pairs, embed them,
build a RAGAS eval harness, implement PII masking views, and store feedback.

### Cross-module contracts
- Requires `analytics.dim_employees` from ingestion (used to generate context for Q&A pairs)
- Adds Postgres schema: `llm` with tables `embeddings`, `eval_results`, `feedback`, `cost_log`
- Adds Postgres view: `llm.safe_employee_context` (PII fields masked)

### Airflow DAG group: `llm_eval`
- `llm_eval_embedding_refresh` — triggered by ingestion DAG on data change
- `llm_eval_nightly` — schedule: `0 2 * * *` (nightly 2am)
  - Tasks: `check_source_freshness` → `refresh_embeddings` → `run_ragas_eval` → `write_cost_log` → `alert_if_scores_drop`

---

## Phase 3 — governance/

**See `governance/TASKS.md` for full implementation details.**

### Summary
Implement a YAML-driven PII classification config, a Python DDL codegen script that generates
Postgres `SECURITY LABEL`, `GRANT`/`REVOKE`, and column masking view statements, plus an
audit trigger on all `restricted` column access.

### Cross-module contracts
- Requires all schemas from ingestion to exist
- Adds Postgres schema: `governance` with tables `access_audit_log`, `classification_registry`
- Modifies existing views in `analytics` schema to apply column-level masking per classification

### Airflow DAG group: `governance_audit`
- Schedule: `0 3 * * 0` (weekly Sunday 3am)
- Tasks: `scan_audit_log` → `flag_unexpected_access` → `send_weekly_report`

---

## Phase 4 — dashboard/

**See `dashboard/TASKS.md` for full implementation details.**

### Summary
Build a three-page Streamlit app (headcount, attrition, recruiting funnel) that queries Trino,
caches results in Postgres, and deploys to Streamlit Community Cloud.

### Cross-module contracts
- Requires Trino catalog and `analytics.*` dbt models from ingestion
- Adds Postgres table: `dashboard.cache` for pre-computed query results
- Deployed public URL must be documented in `dashboard/README.md`

### Airflow DAG group: `dashboard_refresh`
- Schedule: `0 7 * * *` (daily 7am — after ingestion completes)
- Tasks: `refresh_dashboard_cache` → `notify_dashboard_updated`

---

## Phase 5 — linkedin-articles/

**See individual article files. Write after all four projects are implemented and tested.**

Articles are written in first person, under 2,000 words each. Tone: senior engineer explaining
production decisions to other engineers. No marketing language.

---

## Testing strategy

Each module uses the same pattern:

```
tests/
├── unit/          Pure Python — no DB, no Docker. Mock all I/O.
├── integration/   Requires running Postgres (use pytest-docker or testcontainers).
conftest.py        Shared fixtures (DB connection, synthetic data factory).
```

Run integration tests only when Docker is available:
```python
# conftest.py pattern
import pytest
pytestmark = pytest.mark.integration  # mark all integration tests
# run with: pytest -m integration
```

CI (GitHub Actions) runs unit tests on every push, integration tests on PRs to main.

---

## GitHub Actions CI/CD

Each project gets its own workflow at `.github/workflows/{project}-ci.yml`.
The root workflow `.github/workflows/ci.yml` runs `make test-all` on PRs to main.

Standard workflow steps for each module:
1. `actions/checkout`
2. `actions/setup-python@v5` with Python 3.11
3. `pip install -e ".[dev]"`
4. `ruff check src/`
5. `pytest tests/unit/ --cov=src --cov-report=xml`
6. `codecov/codecov-action` (upload coverage)

Integration tests run in a separate job with `services: postgres`.

---

## Definition of done (per module)

- [ ] All source code files implemented (no `TODO` stubs remaining)
- [ ] `make test` passes with ≥80% coverage
- [ ] `make lint-all` passes with zero errors
- [ ] `README.md` includes: purpose, architecture diagram (ASCII), tech stack table, setup instructions, Makefile targets
- [ ] Airflow DAG is visible in UI and runs without errors
- [ ] `docker compose up` from repo root starts the full stack
- [ ] GitHub Actions CI passes on push
