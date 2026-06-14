# LinkedIn article 4 — Streamlit People Analytics dashboard

**Post title:** Building a People Analytics dashboard for non-technical stakeholders with Streamlit, Trino, and a Postgres cache layer (Part 4 of 4)

---

*Part 4 of 4. [Part 3: Sensitive data governance] | [Series intro]*

---

The first three parts of this series were about infrastructure: ingestion, eval pipelines, governance. This part is about the product — the thing a non-engineer can open in a browser and actually use.

Data engineering that stops at the mart layer is half a job. The other half is getting the right information in front of the people who need it, in a form they can act on.

---

**The live dashboard**

[Open dashboard →](https://YOUR-STREAMLIT-URL)

Three views: Headcount, Attrition, Recruiting Funnel.

---

**Architecture**

```
Trino
postgresql.analytics.fct_headcount_daily
postgresql.analytics.fct_attrition_monthly
postgresql.analytics.rpt_recruiting_funnel
         │
         ▼
dashboard.cache (Postgres)
pre-computed query results (refreshed daily by Airflow)
         │
         ▼
Streamlit app
app.py → src/pages/{headcount,attrition,recruiting}.py
         │
         ▼
Deployed: Streamlit Community Cloud (free tier)
```

---

**Why Trino, not direct Postgres**

The dashboard could query Postgres directly. Postgres has the data. It's already running.

But the dashboard queries Trino — the OLAP layer — for the same reason every other analytical consumer in the platform does. The separation between transactional writes (Postgres) and analytical reads (Trino) is an architectural principle, not an implementation detail. Dashboards that query your OLTP database directly start introducing query contention with writes at production scale.

Building the dashboard on Trino demonstrates the pattern, even at a scale where it doesn't matter yet.

---

**The cache layer**

Trino queries on cold start take 2-5 seconds. An HR Partner who opens the dashboard expecting a number and gets a spinner for five seconds will find a different way to get their answer.

The Airflow `dashboard_refresh` DAG runs at 7am daily (one hour after the ingestion DAG completes). It pre-computes all Trino queries for the default filter state and writes results to `dashboard.cache`:

```sql
CREATE TABLE dashboard.cache (
    cache_key   VARCHAR(255) PRIMARY KEY,
    data_json   JSONB NOT NULL,
    computed_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at  TIMESTAMPTZ
);
```

Cache key pattern: `{page}_{filter_hash}_{date}`. The dashboard checks the cache first. On a hit, the page loads in under 500ms. On a miss (uncommon filter combination, or cache expired), it falls through to a live Trino query with a spinner.

---

**Building for non-technical stakeholders**

The engineering work here is largely invisible, which is the point. What's visible to the HR Partner opening the dashboard is:

- A "Last refreshed" timestamp on every panel so they know how fresh the data is
- Filter labels in plain English ("Department", not "dept_id")
- Metric cards with absolute numbers first, percentage change second
- An export button on every page so they can take data to meetings in Excel

That last one matters more than it seems. The first question after "can you show me the attrition rate?" is always "can you send me the raw data?" An export button answers that question before it's asked and eliminates a round-trip to the data team.

The charts use `plotly` with `template="plotly_white"` and accessible axis labels. The theme uses Airbnb's coral (#FF5A5F) as the primary color — a small nod to the intended audience that's also a demonstration of brand-aware data product design.

---

**The three pages**

**Headcount** — three metric cards (total headcount, MoM change, YoY change), a line chart of headcount over time colored by department, and a level distribution bar chart. Filters: department, level, employment type, date range.

**Attrition** — three metric cards (current month rate, rolling 12m rate, YoY change), a dual-line trend chart (monthly rate + rolling 12m), and a department heatmap showing attrition intensity. The involuntary_terminations field is governance-masked for analyst_reader role — the cell shows "(restricted — contact HR)" with a tooltip. This is the governance layer surfacing in the product.

**Recruiting Funnel** — a Plotly funnel chart showing stages with conversion rates, a time-to-hire bar chart by job title, and a monthly application trend line.

---

**Streamlit deployment**

Streamlit Community Cloud is free for public repositories. Deployment takes about 15 minutes:

1. Fork the repository
2. Connect at share.streamlit.io
3. Point at `dashboard/app.py`
4. Add three environment variables (Trino host/port/user)
5. Done — you have a public URL

For a portfolio, a public URL is worth more than any README. A recruiter who can click something and see it working has more confidence than one who reads a description of something working.

---

**What the full platform looks like end-to-end**

```
06:00  hr_ingestion DAG
       extract_workday, extract_greenhouse, extract_airtable
       detect_schema_drift → run_dbt_models → trigger_llm_eval

triggered:
       llm_eval_embedding_refresh
       → refresh pgvector embeddings

02:00  llm_eval_nightly
       → RAGAS eval → write eval_results → alert if scores drop

03:00 Sunday:
       governance_audit
       → scan pg_stat_statements → flag unexpected access → weekly report

07:00  dashboard_refresh
       → pre-compute Trino queries → write to cache → notify Slack
```

Four DAG groups, wired together with sensors and triggers. Every module individually deployable. The full platform deployable from `docker compose up` at the repo root.

---

**Closing the series**

I started this project with a list of gaps and ended with a platform. Not a perfect platform — the audit scanner uses text matching where pg_audit would be stronger, the Streamlit cache strategy is simple where a proper query cache would be smarter, and the mock Workday server is obviously not a real Workday integration.

But production-quality engineering is not about removing all trade-offs. It's about making them deliberately, documenting them honestly, and building systems that are easy to improve as requirements evolve.

All four projects are in the public repository. The dashboard is live.

[GitHub link] · [Live dashboard link]

---

*#dataengineering #streamlit #python #trino #airflow #peopleanalytics #dataproducts #dashboards*
