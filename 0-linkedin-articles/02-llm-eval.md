# LinkedIn article 2 — LLM evaluation infrastructure

**Post title:** Building the data infrastructure for LLM-powered HR tools: pgvector, RAGAS, PII masking, and feedback loops (Part 2 of 4)

---

*Part 2 of 4. [Part 1: HR ingestion pipeline] | [Series intro]*

---

The hardest part of productionising LLM-powered tooling is not the model. The model is almost a detail. The hard part is the data infrastructure around it: how do you feed it safely, evaluate it rigorously, and improve it continuously?

This module is my answer to that question, built on top of the HR data layer from Part 1.

---

**What this module builds**

```
analytics.dim_employees
         │
         ▼
llm.safe_employee_context    ← PII masking view
         │
         ▼
sentence-transformers        ← local embedding encoder (zero cost)
         │
         ▼
llm.embeddings (pgvector)    ← 384-dim vectors, ivfflat index
         │
         ├──► RAGAS eval harness   ──►  llm.eval_results
         │
         ├──► llm.feedback          ←── analyst thumbs up/down
         │
         └──► llm.cost_log          ←── token + cost tracking
```

---

**The PII masking view is the starting point**

Before any data touches an embedding model or an LLM completion, it passes through `llm.safe_employee_context`:

```sql
CREATE OR REPLACE VIEW llm.safe_employee_context AS
SELECT
    employee_id,
    department,
    job_title,
    level,
    hire_date,
    is_active,
    employment_type,
    location,
    MD5(COALESCE(manager_id::text, '')) AS manager_id_hashed
    -- salary: intentionally excluded
    -- performance_rating: intentionally excluded
FROM analytics.dim_employees;
```

This view is not a convenience — it's a security control. The LLM pipeline service account only has `SELECT` on `llm.safe_employee_context`. It cannot reach salary or performance_rating even if a prompt injection tries to exfiltrate them.

This is what "assess data readiness for AI use cases" means in practice. It's a database-level access control, not a prompt engineering note.

---

**Why pgvector over a dedicated vector database**

I could have used Pinecone, Weaviate, or Chroma. I used pgvector for three reasons:

First, the data is already in Postgres. Keeping the vector store in the same database means one less service to operate, one less connection to manage, and transactional consistency between the source data and its embeddings.

Second, Postgres query planning is mature. A `WHERE department = 'Engineering'` pre-filter before the vector similarity search is a standard SQL predicate — pgvector handles it cleanly. With a dedicated vector DB, that pre-filter is usually a metadata filter with different semantics and less predictable performance.

Third, for a People Analytics knowledge base of a few thousand records, pgvector with an `ivfflat` index is more than adequate. The marginal performance gain from a dedicated vector DB does not justify the operational complexity at this scale.

---

**Why sentence-transformers over OpenAI by default**

`sentence-transformers/all-MiniLM-L6-v2` runs locally, costs nothing, has no API dependency, and produces 384-dimensional embeddings. It works offline. It's reproducible. Your CI pipeline can run embedding tests without hitting an API rate limit.

OpenAI `text-embedding-3-small` is available as an opt-in (`EMBEDDING_BACKEND=openai`) for cases where embedding quality is worth the cost. The encoder abstraction makes swapping trivial:

```python
def get_encoder() -> LocalEncoder | OpenAIEncoder:
    backend = os.getenv("EMBEDDING_BACKEND", "local")
    if backend == "openai":
        return OpenAIEncoder()
    return LocalEncoder()
```

The default is always the self-contained option. Defaults that require external API keys are a maintenance liability.

---

**The RAGAS eval harness**

Evaluating RAG systems is a solved problem — RAGAS provides standardised metrics with published benchmarks. I built the harness around four metrics:

| Metric | What it measures |
|---|---|
| Faithfulness | Is the generated answer grounded in the retrieved context? |
| Answer relevancy | Does the answer address the question? |
| Context precision | Are the retrieved chunks relevant to the question? |
| Context recall | Did retrieval find all necessary information? |

The Q&A dataset has 200 pairs across eight question categories (headcount, attrition, tenure, level distribution, location, etc.). Ground truth answers are derived from the actual synthetic data in Postgres — they're not hand-written, which means they stay accurate as the underlying data changes.

Results write to `llm.eval_results`. The nightly Airflow DAG compares scores against the previous run and fires a Slack alert if faithfulness or answer relevancy drop below 0.70.

---

**The feedback loop**

Eval scores measure model quality against ground truth. Human feedback measures usefulness. These are different things and should be stored separately.

```sql
CREATE TABLE llm.feedback (
    id              UUID PRIMARY KEY,
    eval_result_id  UUID REFERENCES llm.eval_results(id),
    analyst_role    VARCHAR(100),      -- 'hr_partner' | 'recruiter' | 'legal'
    rating          SMALLINT           -- 1 (good) | -1 (bad)
        CHECK (rating IN (1, -1)),
    correction_text TEXT               -- optional correction from the analyst
);
```

A model can score 0.85 on faithfulness and still get thumbs-down from HR partners who find the phrasing unhelpful or the framing wrong for their context. Capturing that feedback separately — with the analyst's role — makes it possible to identify patterns: maybe Legal analysts consistently rate attrition-related answers poorly, which points to a gap in the knowledge base, not in the model.

---

**Cost tracking**

Every embedding batch and eval run writes a row to `llm.cost_log`:

```sql
INSERT INTO llm.cost_log (run_type, model_name, embedding_count, input_tokens, cost_usd)
VALUES ('embedding', 'all-MiniLM-L6-v2', 500, NULL, 0.00);
```

For local `sentence-transformers` runs, cost is zero. For OpenAI runs, cost is calculated as `input_tokens * price_per_token` from the model's pricing page. This table becomes the foundation for a cost dashboard — which becomes the justification document when someone asks "why are our AI infrastructure costs $X/month?"

---

**The Airflow DAG wiring**

The embedding refresh DAG has no schedule — it's triggered by the ingestion DAG via `TriggerDagRunOperator` when source data changes. This means embeddings are always fresh relative to the HR data, not fresh relative to a clock.

```
hr_ingestion DAG completes
         │
         ▼ TriggerDagRunOperator
llm_eval_embedding_refresh
         │
         ▼ ExternalTaskSensor
llm_eval_nightly (2am)
```

---

Full code and Docker setup in the repository.

[GitHub link] · Next: Part 3 — Sensitive data governance

---

*#dataengineering #llm #rag #pgvector #ragas #airflow #python #peopleanalytics #aiinfrastructure*
