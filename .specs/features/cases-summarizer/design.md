# cases-summarizer Design

**Spec**: `.specs/features/cases-summarizer/spec.md`
**Context**: `.specs/features/cases-summarizer/context.md`
**Status**: Implemented (2026-06-02)

---

## Architecture Overview

A pull-subscription K8s Deployment that reads pre-converted Markdown files from GCS,
classifies each legal document via OpenAI, and appends structured rows to a Lance table.
KEDA drives scale-to-zero. The upstream cases-pdf-converter job is responsible for
splitting each PDF into per-doc_id Markdown files before this worker runs.

```mermaid
flowchart TD
    PDF[PDF uploaded to GCS] -->|cases-pdf-converter job| MD[GCS: raw/cases_md/{stem}/{doc_id}.md]
    MD -->|OBJECT_FINALIZE| TOPIC[Pub/Sub: cases-md-gcs-events]
    TOPIC --> SUB[Sub: cases-summarizer-md-sub\npull mode]
    SUB --> KEDA[KEDA ScaledObject\nnumUndeliveredMessages]
    KEDA -->|scale 0→N| DEPLOY[K8s Deployment\ncases-summarizer]
    DEPLOY --> WORKER[Worker Pod]
    WORKER -->|1. pull message| SUB
    WORKER -->|2. download .md file| MD
    WORKER -->|3. classify + summarize| OPENAI[OpenAI gpt-4o-mini]
    WORKER -->|4. embed resumo| MODEL[all-MiniLM-L6-v2\npre-baked in image]
    WORKER -->|5. append row| LANCE[Lance: cases_summaries\ngs://justeam/sandbox/default$cases_summaries/]
    LANCE -->|auto-discovered via namespace manifest| TRINO[Trino]
    SUB -->|failed after 5 attempts| DLQ[Topic: cases-md-gcs-events-dlq]
```

---

## Code Reuse Analysis

### Existing Components Leveraged

| Component | Location | How Used |
|---|---|---|
| K8s Deployment pattern | `modules/paperclip/main.tf` — `kubernetes_deployment.paperclip` | env-from-secret, service_account_name |
| K8s ServiceAccount + WI annotation | `modules/paperclip/main.tf` — `kubernetes_service_account.paperclip` | `iam.gke.io/gcp-service-account` annotation |
| K8s Secret | `modules/paperclip/main.tf` — `kubernetes_secret.paperclip_env` | Stores `OPENAI_API_KEY` + `OPENAI_MODEL` |
| Image build null_resource | `apps/spark/image.tf` | SHA-triggered `docker build/push`; now includes `worker.py` in hash |
| GCP SA + IAM bindings | `apps/lakehouse-mcp/k8s.tf` | Dedicated SA, scoped GCS + Pub/Sub roles |
| Embedding model + dim | `apps/spark/jobs/multimodal-products/job.py` | `all-MiniLM-L6-v2`, 384-d, `normalize_embeddings=True` |
| Feature flag wiring | root `main.tf` — `module "keda"` | `count = var.keda ? 1 : 0` |
| Pre-baking model in Dockerfile | `apps/lakehouse-mcp/Dockerfile` | `RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"` |

### New Patterns

- **KEDA ScaledObject** — `modules/keda/` Helm module + `ScaledObject` + KEDA operator GCP SA/WI
- **lancedb namespace manifest** — `LOOP.run(conn.open_table(..., namespace_path=["default"]))` bypasses the Python DirectoryNamespace limitation on Python 3.13

---

## Components

### `modules/keda/`

- **Purpose**: Install KEDA via Helm into the `keda` namespace; create and wire the
  `keda-operator` GCP SA with Workload Identity so KEDA can call GCP Monitoring APIs
- **Location**: `modules/keda/main.tf`, `modules/keda/variables.tf`
- **Resources**:
  1. `helm_release` — KEDA from `kedacore/keda` chart, `keda` namespace
  2. `google_service_account` — `keda-operator@<project>.iam.gserviceaccount.com`
  3. `google_project_iam_member` — `roles/monitoring.viewer` for keda-operator SA
  4. `google_service_account_iam_member` — `roles/iam.workloadIdentityUser` for
     `<project>.svc.id.goog[keda/keda-operator]`
  5. `null_resource` — `kubectl annotate serviceaccount keda-operator` with WI annotation
- **Inputs**: `chart_version` (string, default `"2.16.0"`), `project`
- **Root wiring**: `module "keda" { count = var.keda ? 1 : 0 ... }`

---

### `apps/cases-summarizer/gcp.tf`

- **Purpose**: GCP-side infrastructure — SA, IAM, Pub/Sub topic + subscription + DLQ,
  GCS notification
- **Resources**:
  1. `google_storage_bucket_iam_member` — `roles/storage.legacyBucketReader` for SA
  2. `google_storage_bucket_iam_member` — `roles/storage.objectViewer` on
     `raw/cases_md/` prefix condition
  3. `google_storage_bucket_iam_member` — `roles/storage.objectAdmin` on `sandbox/`
     prefix condition
  4. `google_pubsub_topic` — `cases-md-gcs-events`
  5. `google_pubsub_topic` — `cases-md-gcs-events-dlq`
  6. `google_pubsub_topic_iam_member` — GCS SA publisher on `cases-md-gcs-events`
  7. `google_pubsub_topic_iam_member` — Pub/Sub SA publisher on DLQ topic
  8. `google_storage_notification` — `OBJECT_FINALIZE` on `raw/cases_md/` prefix →
     `cases-md-gcs-events`
  9. `google_pubsub_subscription` — `cases-summarizer-md-sub` (pull, DLQ after 5
     attempts, 600s ack deadline)
  10. `google_pubsub_subscription_iam_member` — subscriber role for cases-summarizer SA
- **Note**: GCP infra lives in `apps/cases-summarizer/` (not a separate module) because
  `apps/cases-summarizer/` is a standalone Terraform root with its own GCS backend
  (`juslake-terraform-state/terraform/cases-summarizer/state`)

---

### `apps/cases-summarizer/image.tf`

- **Purpose**: AR repo + image build + Workload Identity binding for the K8s SA
- **Resources**:
  1. `google_service_account` — `cases-summarizer@<project>.iam.gserviceaccount.com`
  2. `google_artifact_registry_repository` — `cases-summarizer` in `us-central1`
  3. `null_resource` — `docker build + push` triggered by
     `sha256(Dockerfile + pyproject.toml + worker.py)`
  4. `google_service_account_iam_binding` — `roles/iam.workloadIdentityUser` for
     `<project>.svc.id.goog[cases-summarizer/cases-summarizer]`
- **Local**: `image_tag` = first 8 chars of the combined SHA256; `image_uri` built from
  region, project, repo, and tag

---

### `apps/cases-summarizer/k8s.tf`

- **Purpose**: K8s workload resources — namespace, SA, secret, deployment
- **Resources**:
  1. `kubernetes_namespace` — `cases-summarizer`
  2. `kubernetes_service_account` — WI annotation
     `iam.gke.io/gcp-service-account: google_service_account.cases_summarizer.email`
  3. `kubernetes_secret` — `cases-summarizer-env` with `OPENAI_API_KEY`, `OPENAI_MODEL`
  4. `kubernetes_deployment` — 1 container, `env_from` secret ref, env vars:
     `GCS_BUCKET`, `LANCE_URI` (`gs://<bucket>/sandbox`),
     `PUBSUB_SUBSCRIPTION` (`projects/<project>/subscriptions/cases-summarizer-md-sub`)

---

### `apps/cases-summarizer/keda.tf`

- **Purpose**: KEDA scaling resources for the worker deployment
- **Resources**:
  1. `kubernetes_manifest` — KEDA `TriggerAuthentication` (podIdentity: gcp)
  2. `kubernetes_manifest` — KEDA `ScaledObject` (gcp-pubsub scaler,
     subscriptionName=`cases-summarizer-md-sub`, min=0, max=5, targetMessagesPerWorker=1,
     activationMessagesPerWorker=1)
- **Dependencies**: `module.keda` must be applied first (KEDA CRDs must exist)

---

### `apps/cases-summarizer/worker.py`

- **Purpose**: Main processing loop — pulls Pub/Sub messages, loads Markdown, writes to
  Lance
- **Structure**:

```
worker.py
├── SCHEMA                               # pa.schema — 10-column Lance table definition
├── _NAMESPACE = ["default"]             # Lance namespace path for manifest registration
├── _TABLE_NAME = "cases_summaries"
├── main()                               # entry point: instantiates Worker, calls run()
└── class Worker
    ├── __init__()                       # init: storage, subscriber, openai, ST model,
    │                                    # lancedb.connect(LANCE_URI), subscription path
    ├── run()                            # pull loop: subscriber.pull(max_messages=1)
    ├── process_message(message, ack_id) # parse GCS notification → load MD → classify
    │                                    # → embed → write → ack
    ├── load_markdown(file_stem, doc_id) # download raw/cases_md/{stem}/{doc_id}.md;
    │                                    # filter image placeholders (<!-- image --> etc.)
    ├── _build_empty_row(doc_id, stem)   # all string fields "", pagina_* = 0, embedding = []
    ├── is_duplicate(doc_id)             # tbl.search().where("doc_id = '...'").limit(1)
    ├── classify_and_summarize(text)     # OpenAI call → json.loads; retry 3× (1s/2s/4s)
    ├── embed(text)                      # ST model → list[float32] len=384; [] if empty
    ├── write_row(row)                   # pads embedding to 384 zeros if needed;
    │                                    # first write: _open_or_create_table_in_namespace;
    │                                    # subsequent: tbl.add([row]);
    │                                    # attempts create_fts_index + create_index (replace=False)
    ├── _get_table()                     # lazy open: check table_names(namespace_path);
    │                                    # returns None if table does not exist yet
    └── _open_or_create_table_in_namespace(first_row)
                                         # Uses LOOP.run(conn.open_table / conn.create_table)
                                         # with namespace_path=["default"] — bypasses
                                         # Python DirectoryNamespace (unavailable on 3.13)
```

- **Message path format**: `raw/cases_md/{file_stem}/{doc_id}.md`
  (4 parts; must start with `raw/cases_md/`, end with `.md`)
- **Image placeholder filtering**: removes lines matching `<!-- image -->`,
  `<!--image-->`, `<!-- -->`
- **Dependencies**: `openai`, `lancedb`, `sentence-transformers`,
  `google-cloud-storage`, `google-cloud-pubsub`, `pyarrow`
- **Env vars**: `OPENAI_API_KEY`, `OPENAI_MODEL` (default `gpt-4o-mini`),
  `GCS_BUCKET`, `LANCE_URI` (`gs://justeam/sandbox`), `PUBSUB_SUBSCRIPTION`

---

### `apps/cases-summarizer/Dockerfile`

- **Base**: `python:3.13-slim` (project convention)
- **Build steps**:
  1. `uv pip install` from `pyproject.toml`
  2. `RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"` — pre-bakes model (~400MB)
  3. `COPY worker.py /app/`
  4. `CMD ["python", "/app/worker.py"]`

---

## Data Models

### GCS Notification Message (JSON)

```python
{
  "bucket": "justeam",
  "name": "raw/cases_md/{file_stem}/{doc_id}.md",
  ...
}
```

`file_stem` = `parts[2]`, `doc_id` = `parts[3].replace(".md", "")`.

### OpenAI JSON Response

```python
{
  "tipo_documento": "SENTENCA",          # enum
  "polo_emissor": "JUIZ",               # enum
  "data_juntada": "2023-04-15",         # ISO-8601 or null
  "resumo": "[PRELIMINARES_DECIDIDAS]: ..."  # Markdown per template
}
```

Parsed with `json.loads()`. If parse fails → all fields default to `""`.
Text truncated to first 12 000 characters before being sent to the model.

### Lance Row (written via lancedb)

```python
{
  "doc_id":           str,          # from {doc_id}.md filename
  "file_stem":        str,          # from raw/cases_md/{file_stem}/
  "tipo_documento":   str,          # from LLM
  "polo_emissor":     str,          # from LLM
  "data_juntada":     str | None,   # from LLM
  "pagina_inicio":    int,          # always 0 (not applicable to Markdown input)
  "pagina_fim":       int,          # always 0 (not applicable to Markdown input)
  "resumo":           str,          # from LLM (Markdown)
  "resumo_embedding": list[float],  # 384-d float32; zero vector when resumo is empty
  "processed_at":     str,          # datetime.utcnow().isoformat() + "Z"
}
```

### lancedb Write Path

```python
import lancedb
from lancedb.background_loop import LOOP
from lancedb.table import LanceTable

db = lancedb.connect(os.environ["LANCE_URI"])   # "gs://justeam/sandbox"
# Namespace path registers the table in the Lance manifest so Trino discovers it
# as sandbox.default.cases_summaries
async_tbl = LOOP.run(
    db._conn.create_table(
        "cases_summaries",
        data=[first_row],
        schema=SCHEMA,
        namespace_path=["default"],
    )
)
tbl = LanceTable(db, "cases_summaries", namespace_path=["default"], _async=async_tbl)
tbl.add([row_dict])
```

> **Implementation note**: The standard `db.create_table(namespace_path=...)` API requires
> the standalone `lance` Python package which is unavailable for Python 3.13. The internal
> `LOOP.run(db._conn.*)` path is used instead to bypass this limitation.

### OpenAI Prompt (Portuguese)

```
Você é um analisador de documentos jurídicos brasileiros.
Analise o texto fornecido e retorne exclusivamente um JSON com os campos abaixo.
Não inclua texto fora do JSON.

Campos:
- tipo_documento: um dos valores [PETICAO_INICIAL, SENTENCA, CONTESTACAO, DESPACHO]
- polo_emissor: um dos valores [AUTOR, REU, JUIZ, TERCEIRO]
- data_juntada: data de juntada ou protocolo no formato YYYY-MM-DD, ou null se ausente
- resumo: resumo estruturado em Markdown usando o template correspondente ao tipo_documento

Templates por tipo_documento:
PETICAO_INICIAL → [FATOS_CHAVE]: ... \n[TESES_JURIDICAS]: ... \n[PEDIDOS_EFETIVOS]: ... \n[PROVAS_PRODUZIDAS]: ...
SENTENCA        → [PRELIMINARES_DECIDIDAS]: ... \n[FATOS_CONVENCIMENTO]: ... \n[RATIO_DECIDENDI]: ... \n[DISPOSITIVO]: ...
CONTESTACAO     → [PRELIMINARES_ARGUIDAS]: ... \n[TESES_DEFESA]: ... \n[PEDIDOS_DEFESA]: ...
DESPACHO        → [TIPO_DESPACHO]: ... \n[DETERMINACOES]: ... \n[PRAZO]: ...

Texto do documento:
{text[:12000]}
```

---

## Error Handling Strategy

| Error Scenario | Handling | Lance row written? |
|---|---|---|
| OpenAI API error / rate limit | Retry exponential backoff (3×, 1s/2s/4s); on exhaustion → `resumo=""` | Yes (empty resumo) |
| OpenAI returns non-JSON | `json.loads` fails → log WARN, all LLM fields `=""` | Yes (empty resumo) |
| Markdown file text is empty after filtering | Skip LLM call, write row with `resumo=""` | Yes |
| doc_id already in Lance table | Skip entirely (no LLM, no write), log INFO `skipping duplicate` | No |
| Pub/Sub message JSON malformed | Log ERROR, ack message, do not crash | No |
| Unexpected GCS object path | Log WARNING, ack message, do not crash | No |
| Markdown file download fails from GCS | Returns `""` → treated as empty text | Yes (empty row) |
| Lance write fails | Exception propagates → message not acked → retry / DLQ | No |

---

## File Layout

`apps/cases-summarizer/` is a **standalone Terraform root** (own `providers.tf` + GCS
backend), applied separately from the root workspace — same pattern as `apps/spark/`.
GCP infra (SA, IAM, Pub/Sub) co-located here rather than in a separate module.

```
modules/
└── keda/
    ├── main.tf         # helm_release "keda" + keda-operator GCP SA/IAM/WI + kubectl annotate
    └── variables.tf    # chart_version, project

apps/
└── cases-summarizer/
    ├── worker.py           # Python worker
    ├── Dockerfile          # python:3.13-slim + uv + model pre-bake
    ├── pyproject.toml      # uv-managed deps (no pypdf)
    ├── providers.tf        # terraform backend (GCS) + google/kubernetes/null providers
    ├── variables.tf        # project, region, gcs_bucket, openai_api_key, kube_context
    ├── gcp.tf              # GCP SA, IAM bindings, Pub/Sub topics + sub + DLQ, GCS notification
    ├── image.tf            # AR repo + null_resource docker build/push + WI SA→K8s binding
    ├── k8s.tf              # K8s namespace, ServiceAccount (WI annotated), Secret, Deployment
    └── keda.tf             # KEDA ScaledObject + TriggerAuthentication
```

Root `main.tf` additions (module only — GCP infra is in apps/cases-summarizer/):
```hcl
module "keda" {
  count   = var.keda ? 1 : 0
  source  = "./modules/keda"
  project = var.project
}
```

Root `variables.tf` additions: `var.keda` (bool).

---

## Tech Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Input source | Pre-converted Markdown files from `raw/cases_md/` | Decouples PDF conversion from summarization; allows reprocessing without re-converting PDFs |
| Trigger granularity | One Pub/Sub message per doc_id (one `.md` file) | Simplifies worker logic; no regex page-range splitting needed; natural unit for KEDA scaling |
| Worker runtime | K8s Deployment (not Cloud Run) | KEDA pull-mode scaling requires K8s; Cloud Run has no native KEDA integration |
| LanceDB write client | Python `lancedb` internal async API | Spark overhead disproportionate for single-doc writes; standard namespace API requires `lance` package unavailable on Python 3.13 |
| Message processing | One pod per message (`targetMessagesPerWorker: 1`) | Prevents memory contention when multiple docs are processed concurrently |
| Model pre-baking | Download during `docker build`, not at runtime | Avoids ~400MB cold-start download |
| uv for dependencies | `uv pip install` in Dockerfile | Project convention |
| Idempotency key | `doc_id` string (from `.md` filename) | Stable across Pub/Sub re-delivery; unique per physical document |
| KEDA TriggerAuthentication | `podIdentity: provider: gcp` (Workload Identity) | No JSON credentials in cluster |
| GCP infra location | `apps/cases-summarizer/gcp.tf` (not `modules/cases-summarizer/`) | Standalone Terraform root pattern; SA and Pub/Sub are tightly coupled to the app config |
