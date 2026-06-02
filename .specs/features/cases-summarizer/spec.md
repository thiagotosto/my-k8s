# cases-summarizer Specification

**Status:** Implemented (2026-06-02)

## Problem Statement

The existing pipeline converts legal PDFs to per-document Markdown files
(`raw/cases_md/{file_stem}/{doc_id}.md`) via the cases-pdf-converter job. There is no
structured per-case representation: no extracted identifiers, no parties, no judgment data,
no narrative summary. Downstream LLM workflows that need to draft new legal documents have
no queryable source of "what happened in case X" without re-reading raw text chunks.

## Goals

- [x] For every Markdown file written to `gs://justeam/raw/cases_md/`, extract one
  structured record per legal case (doc_id) containing metadata fields and a narrative
  summary
- [x] Persist records to Lance table `cases_summaries` at
  `gs://justeam/sandbox/default$cases_summaries/`, accessible by Trino
- [x] Enable semantic similarity search over summaries via a 384-d vector embedding column
- [x] Enable full-text search over summaries via an FTS index (Portuguese)
- [x] Scale the worker to zero when idle; handle burst uploads up to 5 parallel workers

## Out of Scope

| Feature | Reason |
|---|---|
| Chunk-based segmentation | That is `cases_chunks` / `hierarquical-cases` |
| Batch reprocessing of existing Markdown files | Append-only initially; not needed for MVP |
| Upserts when a file is re-uploaded | Idempotency via skip is sufficient |
| Trino catalog bootstrapping | Table auto-discovered via GCS path convention |
| Multi-language prompts | Documents are Portuguese-only |
| Summary quality scoring / evaluation | No evaluation infra exists today |

---

## User Stories

### P1: Extract structured metadata — ⭐ MVP

**User Story:** As a developer building LLM legal drafting workflows, I want one structured
record per legal case in a Lance table so that I can look up case context (parties, court,
outcome) without re-reading raw PDF text.

**Why P1:** No queryable per-case representation exists today. Everything else depends on
records being written first.

**Acceptance Criteria:**

1. WHEN a Markdown file is uploaded to `raw/cases_md/{file_stem}/{doc_id}.md` AND the
   worker receives the GCS notification via `cases-summarizer-md-sub`
   THEN the worker writes a row to `cases_summaries` containing non-null values for
   `doc_id`, `file_stem`, `tipo_documento`, `polo_emissor`, and `processed_at`,
   plus a non-empty `resumo` whose section tags match the `tipo_documento` template

2. WHEN the worker finishes processing a Markdown file
   THEN `SELECT count(*) FROM sandbox.default.cases_summaries` executed against Trino
   returns a higher count than before processing

3. WHEN N distinct Markdown files arrive for the same `file_stem`
   THEN exactly N rows (minus any already-existing duplicates) are appended to the table

**Independent Test:** Upload a test Markdown file; query Lance table directly and
confirm one new row with correct `doc_id` and `file_stem`.

---

### P1: Generate narrative summary — ⭐ MVP

**User Story:** As a developer building LLM legal drafting workflows, I want a narrative
`resumo` field per case so that I can pass it as context to a drafting LLM without
reconstructing it from raw chunks.

**Why P1:** The summary is the primary artifact that enables downstream LLM workflows.

**Acceptance Criteria:**

1. WHEN the worker processes a doc_id with substantive text
   THEN `resumo` is a non-empty string with typed Markdown sections per `tipo_documento`
   template (argumentations, key documents, procedural history, points relevant for legal
   drafting)
2. WHEN the Markdown file is empty or contains only image placeholders
   THEN `resumo` is stored as `""` and no LLM call is made

**Independent Test:** Inspect `resumo` for a known case; confirm it mentions at least one
of: parties, court, outcome, or a key procedural fact from the source document.

---

### P1: Vector embedding + index — ⭐ MVP

**User Story:** As a developer, I want `resumo_embedding` to enable semantic similarity
queries so that I can find the most relevant past cases for a given legal situation.

**Why P1:** Vector search is the primary retrieval mechanism for LLM drafting context.

**Acceptance Criteria:**

1. WHEN a record is written
   THEN `resumo_embedding` contains a 384-d float32 vector (all-MiniLM-L6-v2,
   normalize_embeddings=True) of `resumo`; when `resumo` is empty, a zero vector is stored
2. WHEN the table has at least 16 rows
   THEN an IVF_PQ index exists on `resumo_embedding` (num_partitions=4, num_sub_vectors=12,
   metric=cosine)
3. WHEN `tbl.search(query_vector).limit(3)` is called
   THEN the top result is more semantically relevant to the query than a random row

**Independent Test:** Run a semantic search with a known legal topic; verify top result
discusses that topic.

---

### P1: FTS index — ⭐ MVP

**User Story:** As a developer, I want full-text search on `resumo` so that I can look up
cases by keyword (party name, legal concept, etc.).

**Why P1:** FTS complements vector search for keyword-specific lookups.

**Acceptance Criteria:**

1. WHEN the table has at least one row
   THEN an FTS index exists on `resumo` (language=Portuguese, lower_case=True, stem=True)
2. WHEN `tbl.search("verbas rescisórias").limit(5)` is called
   THEN results include rows whose summaries mention that term

**Independent Test:** Insert a row with a known keyword; FTS search returns that row.

---

### P2: Scale to zero when idle

**User Story:** As the cluster operator, I want the worker Deployment to have 0 replicas
when there are no pending messages so that I don't pay for idle compute.

**Acceptance Criteria:**

1. WHEN `cases-summarizer-md-sub` has 0 undelivered messages for > 300s
   THEN `kubectl get deployment cases-summarizer -n cases-summarizer` shows `0/0` replicas
2. WHEN a new message arrives
   THEN a replica is started within KEDA's polling interval

**Independent Test:** Drain the subscription; wait 5 min; confirm 0 replicas.

---

### P2: Burst scaling up to 5 replicas

**Acceptance Criteria:**

1. WHEN N Markdown files are uploaded simultaneously (N ≤ 5)
   THEN KEDA scales the Deployment to N replicas (one message per worker)
2. WHEN N > 5 messages are queued
   THEN the Deployment is capped at 5 replicas; remaining messages wait in the subscription

**Independent Test:** Enqueue 3 messages manually; confirm 3 replicas running.

---

### P2: Idempotency

**Acceptance Criteria:**

1. WHEN a Pub/Sub message for a doc_id is re-delivered
   THEN the worker checks if `doc_id` already exists in the Lance table
2. WHEN it does exist
   THEN the doc_id is skipped (no LLM call, no write, logged at INFO)
3. WHEN `SELECT count(*) FROM sandbox.default.cases_summaries` is run before and after
   a re-delivered message is processed
   THEN the counts are equal

**Independent Test:** Process a file; re-deliver the same message; verify row count unchanged.

---

### P2: Dead-letter handling

**Acceptance Criteria:**

1. WHEN a message cannot be processed after `max_delivery_attempts` (5)
   THEN it is forwarded to `cases-md-gcs-events-dlq`
2. WHEN the worker encounters a fatal per-message error
   THEN it acks the message and logs the error rather than crashing

---

### P3: Structured logging

**Acceptance Criteria:**

1. WHEN a message is received
   THEN the worker logs: GCS bucket + object name
2. WHEN the Markdown file is loaded
   THEN the worker logs: `processing doc_id=<id>` and `text_len=<n>`
3. WHEN each doc_id is processed
   THEN the worker logs: `wrote doc_id=<id>` or `skipping duplicate doc_id=<id>`
4. WHEN processing completes
   THEN the worker logs: total elapsed seconds

---

### P3: OpenAI key via K8s Secret

**Acceptance Criteria:**

1. WHEN the worker pod starts
   THEN `OPENAI_API_KEY` is sourced from K8s Secret `cases-summarizer-env`
2. WHEN the secret is absent
   THEN the worker fails to start with a clear error message
3. WHEN the API key is used
   THEN it is never written to logs

---

## Edge Cases

- WHEN the GCS object path does not match `raw/cases_md/{file_stem}/{doc_id}.md` THEN
  the worker logs a warning and acks the message; no rows are written
- WHEN the Markdown file contains only image placeholders (`<!-- image -->` etc.) or is
  empty after filtering THEN no LLM call is made; a row is written with all optional
  fields as `""`, `resumo` as `""`, and a zero vector in `resumo_embedding`
- WHEN the OpenAI API returns an error or rate-limit THEN the worker retries with
  exponential backoff (max 3 attempts: 1s/2s/4s); if all fail, `resumo=""` and error
  is logged
- WHEN the Lance table does not exist yet THEN `lancedb` creates it on first write via
  the internal async connection in the `default` namespace
- WHEN the Pub/Sub message JSON is malformed THEN the worker logs the error, acks the
  message, and does not crash
- WHEN `doc_id` already exists in the Lance table THEN the message is acked and no write
  is performed

---

## Lance Table Schema

Table: `cases_summaries` | Catalog: `sandbox` | Namespace: `default`
GCS path: `gs://justeam/sandbox/default$cases_summaries/`

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `doc_id` | string | No | From `{doc_id}.md` filename (idempotency key) |
| `file_stem` | string | No | PDF/process stem from path `raw/cases_md/{file_stem}/` |
| `tipo_documento` | string | No | Enum: `PETICAO_INICIAL`, `SENTENCA`, `CONTESTACAO`, `DESPACHO` |
| `polo_emissor` | string | No | Enum: `AUTOR`, `REU`, `JUIZ`, `TERCEIRO` |
| `data_juntada` | string | Yes | Filing/attachment date, ISO-8601 or as found in doc (LLM-extracted) |
| `pagina_inicio` | integer | No | Always 0 (page range not applicable to Markdown input) |
| `pagina_fim` | integer | No | Always 0 (page range not applicable to Markdown input) |
| `resumo` | string | Yes | Structured Markdown per tipo_documento template (see below) |
| `resumo_embedding` | list[float32] len=384 | Yes | all-MiniLM-L6-v2 embedding of `resumo`; zero vector when resumo is empty |
| `processed_at` | string | No | ISO-8601 timestamp |

### resumo Templates per tipo_documento

The LLM is instructed to produce Markdown with these typed sections. Agents and downstream
LLMs parse these tags for precision extraction.

**PETICAO_INICIAL**
```
[FATOS_CHAVE]: <facts alleged by the plaintiff>
[TESES_JURIDICAS]: <legal theories invoked>
[PEDIDOS_EFETIVOS]:
- <item 1 (Valor: R$ X if monetary)>
[PROVAS_PRODUZIDAS]: <evidence listed or attached>
```

**SENTENCA**
```
[PRELIMINARES_DECIDIDAS]: <preliminary motions ruled on>
[FATOS_CONVENCIMENTO]: <facts the judge found proven>
[RATIO_DECIDENDI]: <legal reasoning behind the decision>
[DISPOSITIVO]: <operative part — outcome, condemnation amounts, costs>
```

**CONTESTACAO**
```
[PRELIMINARES_ARGUIDAS]: <preliminary defenses raised>
[TESES_DEFESA]: <substantive defenses>
[PEDIDOS_DEFESA]: <relief sought by defendant>
```

**DESPACHO**
```
[TIPO_DESPACHO]: <e.g., saneamento, homologação, intimação>
[DETERMINACOES]: <what the judge ordered>
[PRAZO]: <deadline imposed, if any>
```

Indexes:
- Vector: `IVF_PQ` on `resumo_embedding` (num_partitions=4, num_sub_vectors=12, metric=cosine)
- FTS: on `resumo` (language=Portuguese, lower_case=True, stem=True)

---

## Requirement Traceability

| Requirement ID | Description | Story | Status |
|---|---|---|---|
| SUM-01 | GCS notification on `raw/cases_md/` prefix → `cases-md-gcs-events` topic | P1: metadata | Done |
| SUM-02 | Per-doc_id Markdown download and image-placeholder filtering | P1: metadata | Done |
| SUM-03 | OpenAI document classification: tipo_documento, polo_emissor, data_juntada + tipo-specific resumo | P1: metadata | Done |
| SUM-04 | Structured resumo using per-tipo_documento tagged Markdown template | P1: summary | Done |
| SUM-05 | Lance table schema (10 columns, document-centric) | P1: metadata + summary | Done |
| SUM-06 | Trino accessibility via GCS path convention (namespace manifest) | P1: metadata | Done |
| SUM-07 | Embeddings: all-MiniLM-L6-v2, 384-d, normalized; zero vector when resumo empty | P1: vector | Done |
| SUM-08 | IVF_PQ vector index on resumo_embedding | P1: vector | Done |
| SUM-09 | FTS index on resumo (Portuguese) | P1: FTS | Done |
| SUM-10 | KEDA ScaledObject (gcp-pubsub, min=0, max=5, targetMessagesPerWorker=1) | P2: scaling | Done |
| SUM-11 | Idempotency: skip existing doc_id | P2: idempotency | Done |
| SUM-12 | Pull subscription cases-summarizer-md-sub on cases-md-gcs-events topic | P2: DLQ | Done |
| SUM-13 | Structured logging | P3: logging | Done |
| SUM-14 | OpenAI key via K8s Secret cases-summarizer-env | P3: secret | Done |
| SUM-15 | GCP infra in apps/cases-summarizer/gcp.tf (SA, IAM, Pub/Sub, GCS notification) | P1–P3 | Done |
| SUM-16 | KEDA Helm module modules/keda/ + GCP SA/IAM/WI for keda-operator | P2: scaling | Done |
| SUM-17 | resumo Markdown template enforced per tipo_documento (4 types × defined tags) | P1: metadata + summary | Done |

---

## Success Criteria

- [x] A Markdown file written to `gs://justeam/raw/cases_md/` results in one row per
  legal case in `cases_summaries` within 5 minutes of upload (at steady state)
- [x] `SELECT * FROM sandbox.default.cases_summaries` executes without error in Trino
- [x] A semantic similarity query against `resumo_embedding` returns the most relevant
  case in the top-3 results for a known legal topic query
- [x] With 0 messages in `cases-summarizer-md-sub`, the Deployment has 0 running replicas
- [x] Re-delivering a processed message does not increase the row count in `cases_summaries`
