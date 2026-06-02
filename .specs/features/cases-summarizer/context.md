# cases-summarizer Context

**Gathered:** 2026-05-29  
**Updated:** 2026-06-02  
**Spec:** `.specs/features/cases-summarizer/spec.md`
**Status:** Implemented

---

## Feature Boundary

A standalone Python K8s Deployment (not a Spark job, not Cloud Run) that consumes
`cases-summarizer-md-sub` Pub/Sub messages triggered by GCS Markdown file uploads at
`raw/cases_md/{file_stem}/{doc_id}.md`. Each message maps to exactly one legal case
(doc_id). The worker loads the Markdown text, classifies and summarizes it via OpenAI,
and writes one structured row per doc_id to a Lance table via the `lancedb` Python client.
Scope ends at writing to GCS. No downstream Pub/Sub events are emitted.

---

## Implementation Decisions

### Trigger: one Pub/Sub message per doc_id on cases-md-gcs-events topic

The cases-pdf-converter job (upstream) splits each PDF into individual Markdown files at
`raw/cases_md/{file_stem}/{doc_id}.md`. A GCS notification on the `raw/cases_md/` prefix
publishes to the `cases-md-gcs-events` topic on every `OBJECT_FINALIZE`. The
`cases-summarizer-md-sub` pull subscription on this topic is what KEDA monitors via
`numUndeliveredMessages`. One message = one doc_id = one Lance row (when not duplicate).

This differs from the original design (one message per PDF containing N doc_ids extracted
via pypdf). The Markdown-based approach eliminates in-worker PDF parsing and page-range
extraction entirely.

### Text extraction: download Markdown, filter image placeholders

The worker downloads `raw/cases_md/{file_stem}/{doc_id}.md` from GCS and strips lines
that are image placeholders (`<!-- image -->`, `<!--image-->`, `<!-- -->`). The resulting
text is passed directly to the LLM — no pypdf, no page-range regex.

If the file is empty or reduces to empty after filtering, no LLM call is made and an
empty row is written (all string fields `""`, `resumo_embedding` = zero vector).

### Output: single LLM call for document classification + tipo-specific resumo

One OpenAI API call per doc_id returns a JSON object with 4 fields:
- `tipo_documento` (enum: `PETICAO_INICIAL`, `SENTENCA`, `CONTESTACAO`, `DESPACHO`)
- `polo_emissor` (enum: `AUTOR`, `REU`, `JUIZ`, `TERCEIRO`)
- `data_juntada` (string|null — filing/attachment date, ISO-8601 preferred)
- `resumo` (string — Markdown following the tagged template for the given `tipo_documento`)

Text is truncated to 12 000 characters before being sent to the model.
`pagina_inicio` / `pagina_fim` are stored as 0 — they are not applicable to the
Markdown-based pipeline (page ranges were a PDF-level concept).

### Storage: lancedb internal async API, not standard namespace API

The worker writes to Lance using `LOOP.run(db._conn.create_table(..., namespace_path=["default"]))` 
and wraps the result in `LanceTable(..., namespace_path=["default"])`. This registers the
table in the Lance namespace manifest so Trino discovers it as `sandbox.default.cases_summaries`.

The standard `db.create_table(namespace_path=...)` Python API requires the standalone
`lance` package which is unavailable for Python 3.13. The internal `db._conn.*` path
bypasses this limitation.

### Idempotency: scan Lance table for existing doc_id before LLM call

Before calling the LLM, the worker checks `tbl.search().where("doc_id = '...'").limit(1)`.
If found, the message is acked and no work is done. The table object is lazily initialized
(`_get_table()` returns None until the first write creates it).

### LLM: OpenAI API, gpt-4o-mini by default, Portuguese prompt

Model defaults to `gpt-4o-mini` (configurable via `OPENAI_MODEL` env var). The prompt is
written in Portuguese to match the documents' language. API key sourced from K8s Secret
`cases-summarizer-env` — never hardcoded or logged.

### Embedding: all-MiniLM-L6-v2, 384-d — same as cases_chunks

Same model and dimension as the `text_embedding` column in `cases_chunks`, enabling
cross-table semantic similarity. Stored in `resumo_embedding`. When `resumo` is empty, a
zero vector (`[0.0] * 384`) is stored to satisfy the fixed-dimension schema constraint.
Model is pre-baked into the Docker image during build (~400MB).

### Infrastructure: GCP infra co-located in apps/cases-summarizer/gcp.tf

No separate `modules/cases-summarizer/` module exists. All GCP resources (SA, IAM,
Pub/Sub topic + subscription + DLQ, GCS notification) are defined in
`apps/cases-summarizer/gcp.tf` because `apps/cases-summarizer/` is a standalone Terraform
root with its own GCS backend. The GCP SA is created in `image.tf` (alongside the AR repo)
rather than `gcp.tf`.

### KEDA: new modules/keda/ module, Helm chart + operator WI

`modules/keda/` installs KEDA via Helm and also provisions the `keda-operator` GCP SA with
`roles/monitoring.viewer` + Workload Identity binding, then annotates the K8s SA via
`kubectl annotate`. The KEDA CRDs (TriggerAuthentication, ScaledObject) are applied in
`apps/cases-summarizer/keda.tf` after `module.keda` is applied.

### Scaling: min=0, max=5, one message per worker

`minReplicaCount: 0`, `maxReplicaCount: 5`. `targetMessagesPerWorker: 1` and
`activationMessagesPerWorker: 1`. KEDA wakes the deployment when at least 1 message is
queued. `TriggerAuthentication` uses `podIdentity: provider: gcp` (Workload Identity).

### Docker image: python:3.13-slim, no pypdf

Image contains: `openai`, `lancedb`, `sentence-transformers`, `google-cloud-storage`,
`google-cloud-pubsub`, `pyarrow`. `pypdf` is **not** included — Markdown input makes it
unnecessary. `all-MiniLM-L6-v2` is pre-baked. Pushed to AR repo `cases-summarizer`.

---

## Specific References

- lancedb internal async write path:
  `apps/cases-summarizer/worker.py` — `_open_or_create_table_in_namespace()`
- GCS notification on Markdown prefix:
  `apps/cases-summarizer/gcp.tf` — `google_storage_notification.cases_md`
- KEDA operator WI setup:
  `modules/keda/main.tf` — `google_service_account.keda_operator` + `null_resource.annotate_keda_operator_sa`
- Pub/Sub subscription and topic:
  `apps/cases-summarizer/gcp.tf` — `cases-md-gcs-events`, `cases-summarizer-md-sub`
- Embedding model/dim/normalization:
  `apps/spark/jobs/multimodal-products/job.py` — `all-MiniLM-L6-v2`, 384-d
- Lance GCS path convention:
  `gs://justeam/sandbox/default$cases_summaries/`

---

## Deferred Ideas

- **Upserts on file re-upload:** Update existing records rather than skipping — deferred, append-only is sufficient for now
- **Summary quality evaluation:** ROUGE or LLM-as-judge scoring — deferred, no eval infra exists
- **Expose pagina_inicio/pagina_fim:** Could be derived from the Markdown file path or a sidecar metadata file if needed downstream — deferred
- **Downstream events:** Publish `cases-summaries-events` topic after write to trigger further enrichment — deferred, no consumer identified yet
- **Correction re-summarization:** Trigger re-processing via Pub/Sub message (not GCS upload) — deferred until summary quality is validated
