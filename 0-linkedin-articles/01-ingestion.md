# LinkedIn article 1 — HR ingestion pipeline

**Post title:** How I built a production-grade HR data ingestion pipeline with Python, Postgres, dbt, and Trino (Part 1 of 4)

---

*Part 1 of 4 in the workforce-intelligence-platform series. [Series intro here.]*

---

The first module in the platform is the foundation everything else sits on. If this layer is wrong, the LLM eval scores are wrong, the governance classification is applied to the wrong schema, and the dashboard shows garbage. So I built it first, and I built it with more care than the other three combined.

Here's what it does, how it's structured, and the decisions I'd make the same way again.

---

**Architecture**

```
Workday API (mock)     Greenhouse API (mock)     Airtable API (real)
      │                        │                        │
      ▼                        ▼                        ▼
WorkdayConnector     GreenhouseConnector       AirtableConnector
      │                        │                        │
      └────────────────────────┴────────────────────────┘
                               │
                         raw.employees
                      raw.job_applications
                               │
                           dbt models
                     stg_employees (view)
                     stg_job_applications (view)
                               │
                    dim_employees (table)
                    fct_headcount_daily (table)
                    fct_attrition_monthly (table)
                    rpt_recruiting_funnel (table)
                               │
                           Trino OLAP
```

**Tech stack**

| Layer | Technology |
|---|---|
| Language | Python 3.11 |
| HTTP | httpx + tenacity |
| Validation | Pydantic v2 |
| Database | Postgres 16 |
| Transforms | dbt-core 1.8 |
| OLAP | Trino 438 |
| Orchestration | Airflow 2.9 |

---

**Three connectors, one interface**

All three source connectors implement the same abstract base:

```python
class BaseConnector(ABC):
    @abstractmethod
    def fetch_employees(self) -> Iterator[EmployeeRaw]: ...
    @abstractmethod
    def fetch_job_applications(self) -> Iterator[JobApplicationRaw]: ...
```

This matters for two reasons. First, the Airflow DAG can treat all three connectors identically — it doesn't need to know which one it's running. Second, adding a fourth source (say, a Lever ATS or a Rippling HRIS) is a matter of writing one new class and registering it, not modifying the pipeline logic.

The Workday and Greenhouse connectors talk to a local Flask mock server I built using `faker`. The Airtable connector uses a real Airtable account with a free Personal Access Token — the repo includes instructions for setting up the base in about 10 minutes.

---

**Why upsert over truncate-load**

The instinctive approach for a batch pipeline is truncate-load: delete everything, re-insert. It's simple. It guarantees freshness.

It also means if your downstream dbt models have already materialized from the old data and your load fails halfway through, you have an inconsistent state with no clean rollback path.

I used `INSERT ... ON CONFLICT (source, source_id) DO UPDATE` throughout. Idempotent upserts mean the DAG can be re-run safely, mid-failure restarts from the last successful batch, and the raw layer always reflects the most recent state of each source record without full replacement.

---

**The schema drift detector**

One of the most underappreciated failure modes in data pipelines is silent schema drift. An upstream system adds a new field — or worse, renames an existing one — and your pipeline keeps running, silently dropping or misrouting data.

I built a lightweight drift detector that runs on every ingestion batch:

```python
def detect_drift(
    source: str,
    new_records: list[dict],
    baseline_schema: dict[str, str],
    pii_fields: set[str],
) -> list[DriftEvent]:
```

It infers the schema from the incoming records, compares against a stored baseline, and categorises changes as `added`, `removed`, or `type_changed`. Any drifted field that appears in the PII fields set triggers a Slack alert immediately — before the dbt run. The reasoning: PII field changes carry compliance implications and should never be silently ingested.

---

**Why salary and performance_rating are not in dim_employees**

The `analytics.dim_employees` mart intentionally excludes salary and performance_rating. These fields exist in the raw layer — they come through the Workday connector — but they're stripped before hitting the analytics schema.

This is not an oversight. It's a design decision.

The governance module (Part 3) re-introduces these columns as `restricted`-classified fields accessible only to HR Partner and Legal roles. By excluding them from the default dimension, I make the safe path the easy path: an analyst who queries `dim_employees` cannot accidentally expose restricted data, even if they `SELECT *`.

The pattern mirrors how production HR data systems are actually designed at companies that take data privacy seriously.

---

**Trino on top of Postgres**

Postgres is the OLTP source of truth. Trino adds a federated OLAP query layer on top without copying data. The dashboard (Part 4) and ad-hoc analysts hit Trino, which pushes predicates down to Postgres.

At portfolio scale, this is over-engineered. At production scale — where you might have Postgres for HR data, BigQuery for event data, and S3 for unstructured data — Trino as a unified query layer is exactly the right architecture. Building it this way now means the pattern is demonstrated, not just described.

---

**The Airflow DAG**

The `hr_ingestion` DAG runs daily at 6am:

```
extract_workday ──┐
extract_greenhouse ├──► detect_schema_drift ──► run_dbt_models ──► alert_on_pii_change ──► trigger_llm_eval
extract_airtable ──┘
```

The three extract tasks run in parallel. Schema drift detection gates the dbt run — if a PII field drifted, the alert fires before models run, giving an operator the chance to inspect before potentially bad data flows downstream.

The final task triggers the `llm_eval_embedding_refresh` DAG via `TriggerDagRunOperator`, so the embedding store always reflects the latest employee data.

---

The full code, Docker Compose setup, and dbt models are in the repository.

[GitHub link] · Next: Part 2 — LLM evaluation infrastructure

---

*#dataengineering #python #dbt #trino #airflow #postgres #peopleanalytics*
