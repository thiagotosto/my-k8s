# cases-summarizer Tasks

**Design**: `.specs/features/cases-summarizer/design.md`
**Status**: Draft

---

## Execution Plan

```
Phase 1 — Foundation (all parallel):
  T1 [P] ──────────────────────────────────────────────┐
  T2 [P] ──────────────────────────┬───────────────────┤
  T3 [P] ──────────────────┬───────┤                   │
                            │       │                   │
Phase 2 — Core (parallel):  ↓       ↓                   ↓
                           T5 [P] T6 [P]              T4 [P]
                            │       │
Phase 3 — K8s workload:     └───┬───┘
                                ↓
                               T7
                                │
Phase 4 — KEDA scaling:    T1 ──┴──→ T8
                                        │
Phase 5 — Smoke test:                   └──→ T9
```

### Dependency Summary

| Task | Depends on |
|------|------------|
| T1 | None |
| T2 | None |
| T3 | None |
| T4 | T1, T2 |
| T5 | T3 |
| T6 | T2, T3 |
| T7 | T5, T6 |
| T8 | T1, T7 |
| T9 | T8 |

---

## Task Breakdown

### T1: modules/keda/ — KEDA Helm module [P]

**What**: Create `modules/keda/main.tf` and `variables.tf` — installs KEDA via the official `kedacore/keda` Helm chart into the `keda` namespace
**Where**: `modules/keda/main.tf`, `modules/keda/variables.tf`
**Depends on**: None
**Reuses**: Helm release pattern from `modules/spark-operator/` (same Helm provider, same chart install shape)
**Requirement**: SUM-16

**Done when**:
- [ ] `helm_release "keda"` defined with chart `keda`, repo `https://kedacore.github.io/charts`, namespace `keda`, `create_namespace = true`
- [ ] `var.chart_version` with a sensible default (e.g. `"2.16.0"`)
- [ ] `terraform validate` passes from root workspace after `terraform init`

**Tests**: none
**Gate**: Quick — `terraform validate` (run from project root after `terraform init`)

**Commit**: `feat(keda): add KEDA Helm module`

---

### T2: modules/cases-summarizer/ — GCP infra [P]

**What**: Create `modules/cases-summarizer/` with `main.tf`, `variables.tf`, `outputs.tf` — provisions GCP SA, IAM bindings (GCS + Pub/Sub), and the pull subscription with DLQ
**Where**: `modules/cases-summarizer/main.tf`, `variables.tf`, `outputs.tf`
**Depends on**: None
**Reuses**: Pull subscription shape from `modules/cases-pdf-processor/main.tf` (`google_pubsub_subscription` with no `push_config`, dead_letter_policy, retry_policy); GCP SA + IAM binding pattern from same file
**Requirement**: SUM-12, SUM-15

**Resources to create**:
1. `google_service_account` — `cases-summarizer`
2. `google_project_iam_member` × 2 — `roles/storage.objectViewer` on `raw/cases_pdf/` prefix condition; `roles/storage.objectAdmin` on `sandbox/` prefix condition
3. `google_pubsub_subscription` — `cases-summarizer-sub`: pull mode, `ack_deadline_seconds = 600`, DLQ after 5 attempts pointing to `cases-pdf-gcs-events-dlq`
4. `google_pubsub_subscription_iam_member` — `roles/pubsub.subscriber` for the SA

**Inputs**: `project` (string), `region` (string), `gcs_bucket` (string)
**Outputs**: `sa_email` — the GCP SA email consumed by `apps/cases-summarizer/`

**Done when**:
- [ ] All 4 resource types defined
- [ ] `outputs.tf` exports `sa_email`
- [ ] Pull subscription has no `push_config` block
- [ ] DLQ points to existing `cases-pdf-gcs-events-dlq` topic (variable, not hardcoded)
- [ ] `terraform validate` passes from root workspace

**Tests**: none
**Gate**: Quick — `terraform validate`

**Commit**: `feat(cases-summarizer): add GCP infra module (SA, IAM, Pub/Sub subscription)`

---

### T3: Python project setup — pyproject.toml + Dockerfile [P]

**What**: Create `apps/cases-summarizer/pyproject.toml` (uv-managed deps) and `Dockerfile` (python:3.13-slim + uv install + model pre-bake)
**Where**: `apps/cases-summarizer/pyproject.toml`, `apps/cases-summarizer/Dockerfile`
**Depends on**: None
**Reuses**:
- Base image `python:3.13-slim` (project convention per memory)
- `uv pip install` pattern (project convention)
- ST model pre-bake RUN line pattern from `cases-pdf-converter` Dockerfile
**Requirement**: —

**Dependencies (pyproject.toml)**:
```
pypdf, openai, lancedb, sentence-transformers, google-cloud-storage, google-cloud-pubsub, pyarrow
```

**Dockerfile steps**:
1. `FROM python:3.13-slim`
2. Install uv, then `uv pip install` from pyproject.toml
3. Pre-bake model: `RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"`
4. `COPY worker.py /app/`
5. `CMD ["python", "/app/worker.py"]`

**Done when**:
- [ ] `pyproject.toml` lists all 7 dependencies with pinned major versions
- [ ] Dockerfile uses `python:3.13-slim` base
- [ ] Dockerfile uses `uv` for package installation (not pip)
- [ ] Model pre-bake RUN line present
- [ ] `COPY worker.py /app/` present (worker.py written in T5)
- [ ] `CMD ["python", "/app/worker.py"]` present

**Tests**: none
**Gate**: none (Dockerfile build verified once worker.py exists in T5; flagged for manual `docker build` after T5)

**Commit**: `feat(cases-summarizer): add Python project setup (Dockerfile + pyproject.toml)`

---

### T4: Root TF additions — var.keda, var.cases_summarizer, module blocks [P]

**What**: Add `var.keda` (bool), `var.cases_summarizer` (bool), `var.openai_api_key` (sensitive string) to root `variables.tf` + `terraform.tfvars`; wire `module "keda"` and `module "cases_summarizer"` blocks into root `main.tf`
**Where**: `variables.tf`, `terraform.tfvars`, `main.tf` (root)
**Depends on**: T1, T2 (module source paths must exist for `terraform validate` to pass)
**Reuses**: Feature-flag module wiring pattern from root `main.tf` — `module "cases_pdf_processor"` block (same `count = var.X ? 1 : 0` shape)
**Requirement**: SUM-15, SUM-16

**Done when**:
- [ ] `var.keda` (bool, default `false`) and `var.cases_summarizer` (bool, default `false`) in `variables.tf`
- [ ] `var.openai_api_key` (string, sensitive, no default) in `variables.tf`
- [ ] `terraform.tfvars` has stub entries: `keda = false`, `cases_summarizer = false`
- [ ] `module "keda"` block in `main.tf` with `count = var.keda ? 1 : 0`
- [ ] `module "cases_summarizer"` block in `main.tf` with `count = var.cases_summarizer ? 1 : 0`, passing `project`, `region`, `gcs_bucket`
- [ ] `terraform validate` passes from root workspace
- [ ] `terraform plan` produces no errors (run with `cases_summarizer=false, keda=false` to avoid needing cluster)

**Tests**: none
**Gate**: Full — `terraform validate && terraform plan`

**Commit**: `feat(root): wire keda and cases-summarizer modules behind feature flags`

---

### T5: apps/cases-summarizer/worker.py [P]

**What**: Implement the full Python worker — Pub/Sub pull loop, PDF download, doc-range extraction, idempotency check, OpenAI classification + structured resumo, embedding, Lance write, structured logging, error handling
**Where**: `apps/cases-summarizer/worker.py`
**Depends on**: T3 (needs pyproject.toml to know available libs)
**Reuses**:
- `all-MiniLM-L6-v2` embedding pattern from `apps/spark/jobs/hierarquical-cases/job.py` (model init, `normalize_embeddings=True`)
- Regex pattern `r"Num\. (\d+) - Pág\. (\d+)"` (same as cases-pdf-indexer)
- lancedb write path from design.md Data Models section (PyArrow schema + `db.create_table` / `tbl.add`)
- OpenAI prompt templates from `spec.md` resumo section
**Requirement**: SUM-01, SUM-02, SUM-03, SUM-04, SUM-05, SUM-06, SUM-07, SUM-08, SUM-09, SUM-11, SUM-13, SUM-17

**Class structure** (from design.md):
- `Worker.__init__`: init pubsub, storage, lancedb, openai, ST model clients
- `Worker.run()`: pull loop
- `Worker.process_message(msg)`: download → extract → process each doc_id → ack
- `Worker.extract_doc_ranges(pdf)`: regex → list[(doc_id, p_start, p_end)]
- `Worker.extract_text(pdf, p1, p2)`: pypdf page slice → str
- `Worker.is_duplicate(doc_id)`: Lance scan WHERE doc_id = X
- `Worker.classify_and_summarize(text)`: OpenAI → parsed JSON
- `Worker.embed(text)`: ST model → list[float32] len=384
- `Worker.write_row(row)`: lancedb append (create table on first write)

**Done when**:
- [ ] All 8 class methods implemented
- [ ] LLM prompt includes all 4 resumo templates verbatim (PETICAO_INICIAL, SENTENCA, CONTESTACAO, DESPACHO)
- [ ] Idempotency check scans Lance before any LLM call
- [ ] OpenAI retry with exponential backoff (3 attempts, 1s/2s/4s)
- [ ] Empty text → write row with `resumo=""`, no LLM call
- [ ] Malformed Pub/Sub JSON → log ERROR, ack, no crash
- [ ] Structured logging: received bucket/object, doc_ids found count, per-doc_id status, total elapsed
- [ ] Env vars: `OPENAI_API_KEY`, `OPENAI_MODEL` (default `gpt-4o-mini`), `GCS_BUCKET`, `LANCE_URI`
- [ ] lancedb schema matches spec (10 columns: doc_id, file_stem, tipo_documento, polo_emissor, data_juntada, pagina_inicio, pagina_fim, resumo, resumo_embedding, processed_at)
- [ ] IVF_PQ index on `resumo_embedding` and FTS index on `resumo` created after first write (or on table open)
- [ ] `⚠️ lancedb GCS API`: verify `lancedb.connect("gs://...")` and table name `"default$cases_summaries"` against lancedb docs before writing (flagged uncertainty from design.md)

**Tests**: none
**Gate**: none (manual — inspect code; full functional gate after T7/T8 via deployment smoke test)

**Commit**: `feat(cases-summarizer): implement Python worker`

---

### T6: apps/cases-summarizer/image.tf + variables.tf [P]

**What**: Create `apps/cases-summarizer/image.tf` (AR repo + null_resource image build + WI SA→K8s binding) and `variables.tf` for the apps workspace
**Where**: `apps/cases-summarizer/image.tf`, `apps/cases-summarizer/variables.tf`
**Depends on**: T2 (needs `sa_email` output), T3 (Dockerfile exists for SHA hash trigger)
**Reuses**: `null_resource` image build pattern from `apps/spark/image.tf` (sha256 trigger on Dockerfile + pyproject.toml, local-exec docker build + push); AR repo resource from `modules/cases-pdf-processor/main.tf`
**Requirement**: —

**Done when**:
- [ ] `variables.tf` declares: `project`, `region`, `gcs_bucket`, `openai_api_key` (sensitive), `sa_email`, `kube_context`
- [ ] `google_artifact_registry_repository "cases_summarizer"` defined (format: `DOCKER`, location: `var.region`)
- [ ] `null_resource "build_push"` with `triggers` on `sha256(file("Dockerfile"))` + `sha256(file("pyproject.toml"))` and local-exec `docker build` + `docker push` to AR
- [ ] `google_service_account_iam_binding "workload_identity"` binds GCP SA (`var.sa_email`) to K8s SA (`serviceAccount:<project>.svc.id.goog[cases-summarizer/cases-summarizer]`)
- [ ] `terraform validate` passes from `apps/cases-summarizer/`

**Tests**: none
**Gate**: Quick — `cd apps/cases-summarizer && terraform validate`

**Commit**: `feat(cases-summarizer): add image build and Workload Identity Terraform`

---

### T7: apps/cases-summarizer/k8s.tf

**What**: Create `apps/cases-summarizer/k8s.tf` — K8s namespace, ServiceAccount (WI annotated), Secret (`cases-summarizer-env`), and Deployment
**Where**: `apps/cases-summarizer/k8s.tf`
**Depends on**: T5 (worker.py baked into image), T6 (image URI available from AR repo)
**Reuses**: K8s Deployment + ServiceAccount + Secret pattern from `modules/paperclip/main.tf` (`kubernetes_namespace`, `kubernetes_service_account` with WI annotation, `kubernetes_secret`, `kubernetes_deployment` with `env_from` secret ref)
**Requirement**: SUM-14

**Done when**:
- [ ] `kubernetes_namespace "cases_summarizer"` defined
- [ ] `kubernetes_service_account "cases_summarizer"` with annotation `iam.gke.io/gcp-service-account = var.sa_email`
- [ ] `kubernetes_secret "cases_summarizer_env"` with keys: `OPENAI_API_KEY` (from `var.openai_api_key`), `OPENAI_MODEL` (default `gpt-4o-mini`)
- [ ] `kubernetes_deployment "cases_summarizer"` with:
  - 0 initial replicas (KEDA will manage count)
  - container image referencing AR repo URI from `image.tf`
  - `env_from` sourcing `cases-summarizer-env` secret
  - env vars: `GCS_BUCKET = var.gcs_bucket`, `LANCE_URI = "gs://${var.gcs_bucket}/sandbox"`
  - `service_account_name = kubernetes_service_account.cases_summarizer.metadata[0].name`
- [ ] `terraform validate` passes from `apps/cases-summarizer/`

**Tests**: none
**Gate**: Quick — `cd apps/cases-summarizer && terraform validate`

**Commit**: `feat(cases-summarizer): add K8s namespace, SA, secret, and deployment Terraform`

---

### T8: apps/cases-summarizer/keda.tf

**What**: Create `apps/cases-summarizer/keda.tf` — KEDA `TriggerAuthentication` (Workload Identity) and `ScaledObject` (gcp-pubsub scaler, min=0, max=5)
**Where**: `apps/cases-summarizer/keda.tf`
**Depends on**: T1 (KEDA CRDs must be installed), T7 (Deployment must exist as ScaledObject target)
**Reuses**: No existing ScaledObject in codebase — implement per KEDA gcp-pubsub scaler docs
**Requirement**: SUM-10

**Done when**:
- [ ] `kubernetes_manifest "trigger_auth"` defines a `TriggerAuthentication` with `podIdentity.provider: gcp` (Workload Identity — no secret credentials)
- [ ] `kubernetes_manifest "scaled_object"` defines a `ScaledObject` with:
  - `scaleTargetRef.name: cases-summarizer`
  - `minReplicaCount: 0`, `maxReplicaCount: 5`
  - trigger type `gcp-pubsub`, subscription `cases-summarizer-sub`
  - `targetMessagesPerWorker: "1"` (one message per replica)
  - `authenticationRef` pointing to the TriggerAuthentication above
- [ ] `terraform validate` passes from `apps/cases-summarizer/`

**Tests**: none
**Gate**: Quick — `cd apps/cases-summarizer && terraform validate`

**Commit**: `feat(cases-summarizer): add KEDA ScaledObject for scale-to-zero`

---

## Parallel Execution Map

```
Phase 1 (all independent — run in parallel):
  T1 [P]  T2 [P]  T3 [P]
   │        │  └───────────────────────────┐
   │        └──────────────────┐           │
   │                           │           │
Phase 2 (after Phase 1 deps — run in parallel):
   │        T2,T3 ──→ T6 [P]  T3 ──→ T5 [P]  T1,T2 ──→ T4 [P]
   │                  │              │
Phase 3 (T5 + T6 done):
   │             T5,T6 ──────→ T7
   │                            │
Phase 4 (T1 + T7 done):         │
   └──────────── T1,T7 ─────────┴──→ T8
```

---

## Task Granularity Check

| Task | Scope | Status |
|------|-------|--------|
| T1: modules/keda/ (main.tf + variables.tf) | 2 files, 1 module | ✅ Granular |
| T2: modules/cases-summarizer/ (3 TF files) | 3 files, 1 module, cohesive | ✅ Granular |
| T3: pyproject.toml + Dockerfile | 2 files, 1 Docker build context | ✅ Granular |
| T4: Root TF additions (variables.tf + tfvars + main.tf) | 3 files, 1 logical change | ✅ Granular |
| T5: worker.py | 1 file | ✅ Granular |
| T6: image.tf + variables.tf | 2 files, 1 apps workspace foundation | ✅ Granular |
| T7: k8s.tf | 1 file | ✅ Granular |
| T8: keda.tf | 1 file | ✅ Granular |
| T9: e2e smoke test (wuquiria.pdf) | 0 files, 1 verification sequence | ✅ Granular |

---

## Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
|------|------------------------|---------------|--------|
| T1 | None | No incoming arrows | ✅ Match |
| T2 | None | No incoming arrows | ✅ Match |
| T3 | None | No incoming arrows | ✅ Match |
| T4 | T1, T2 | T1→T4, T2→T4 | ✅ Match |
| T5 | T3 | T3→T5 | ✅ Match |
| T6 | T2, T3 | T2→T6, T3→T6 | ✅ Match |
| T7 | T5, T6 | T5→T7, T6→T7 | ✅ Match |
| T8 | T1, T7 | T1→T8, T7→T8 | ✅ Match |

---

## Test Co-location Validation

Per `TESTING.md`, all code layers in this project have **test type: none** (manual validation via
`terraform validate`, `terraform plan`, and manual deployment verification). No automated test
framework exists.

| Task | Code Layer | Matrix Requires | Task Says | Status |
|------|------------|-----------------|-----------|--------|
| T1 | Terraform module | none (validate) | none / Quick gate | ✅ OK |
| T2 | Terraform module | none (validate) | none / Quick gate | ✅ OK |
| T3 | Dockerfile + pyproject.toml | none (manual) | none | ✅ OK |
| T4 | Root Terraform | none (validate + plan) | none / Full gate | ✅ OK |
| T5 | Python worker | none (manual) | none | ✅ OK |
| T6 | Terraform (apps workspace) | none (validate) | none / Quick gate | ✅ OK |
| T7 | Terraform (apps workspace) | none (validate) | none / Quick gate | ✅ OK |
| T8 | Terraform (apps workspace) | none (validate) | none / Quick gate | ✅ OK |

---

### T9: End-to-end smoke test — wuquiria.pdf

**What**: Delete and re-upload `gs://justeam/raw/cases_pdf/wuquiria.pdf` to trigger the full pipeline; verify that the worker scales up, processes the document, and writes correct rows to the Lance table
**Where**: GCS + K8s + Lance table (no file changes — pure verification)
**Depends on**: T8 (all infra deployed and `terraform apply` run in both root and apps workspaces)
**Reuses**: `gsutil`, `kubectl`, `lancedb` Python client, `trino` Python client
**Requirement**: SUM-01–SUM-09, SUM-10, SUM-11, SUM-13, SUM-06 (functional validation of all P1 + P2 requirements)

**Steps**:
```bash
# 1. Delete + re-upload to fire OBJECT_FINALIZE
gsutil rm -f gs://justeam/raw/cases_pdf/wuquiria.pdf
gsutil cp <local-path>/wuquiria.pdf gs://justeam/raw/cases_pdf/wuquiria.pdf

# 2. Watch KEDA scale up
kubectl get deployment cases-summarizer -n cases-summarizer -w

# 3. Stream worker logs
kubectl logs -n cases-summarizer -l app=cases-summarizer -f

# 4. Query Lance table (run from Python REPL or inline script)
python3 - <<'EOF'
import lancedb
db = lancedb.connect("gs://justeam/sandbox")
tbl = db.open_table("default$cases_summaries")
rows = tbl.search().where("file_stem = 'wuquiria'").to_list()
for r in rows:
    print(r["doc_id"], r["tipo_documento"], r["polo_emissor"], r["pagina_inicio"], r["pagina_fim"])
    print(r["resumo"][:300])
    print("embedding len:", len(r["resumo_embedding"]))
    print("---")
EOF

# 5. Verify Trino accessibility (SUM-06)
kubectl port-forward -n trino svc/trino 8080:8080 &
PF_PID=$!
sleep 3

python3 - <<'EOF'
import trino

conn = trino.dbapi.connect(host="localhost", port=8080, user="trino")
cur = conn.cursor()
cur.execute("SELECT count(*) FROM sandbox.default.cases_summaries")
count = cur.fetchone()[0]
print(f"cases_summaries row count via Trino: {count}")
assert count >= 1, f"Expected ≥1 rows, got {count}"

cur.execute("SELECT doc_id, tipo_documento, polo_emissor FROM sandbox.default.cases_summaries LIMIT 3")
rows = cur.fetchall()
for r in rows:
    print(r)
conn.close()
EOF

kill $PF_PID

# 6. Verify scale-to-zero after cooldown (~5 min)
kubectl get deployment cases-summarizer -n cases-summarizer
```

**Done when**:
- [ ] Upload triggers at least one pod scaling up (`0/0` → `1/1`)
- [ ] Worker logs show: GCS object received, N doc_ids found, `processing doc_id=X`, `wrote doc_id=X` for each doc
- [ ] Lance table has ≥1 row with `file_stem = 'wuquiria'`
- [ ] Each row has non-empty `tipo_documento` ∈ {PETICAO_INICIAL, SENTENCA, CONTESTACAO, DESPACHO}
- [ ] Each row has non-empty `polo_emissor` ∈ {AUTOR, REU, JUIZ, TERCEIRO}
- [ ] Each row's `resumo` contains the expected section tags for its `tipo_documento` (e.g., `[DISPOSITIVO]` for SENTENCA)
- [ ] `len(resumo_embedding) == 384` for every row
- [ ] `pagina_inicio` and `pagina_fim` are integers matching the source doc_id page ranges
- [ ] Re-uploading the same PDF a second time produces no new rows (idempotency — SUM-11)
- [ ] `SELECT count(*) FROM sandbox.default.cases_summaries` via Trino returns ≥1 without error (SUM-06)
- [ ] `SELECT doc_id, tipo_documento, polo_emissor FROM sandbox.default.cases_summaries LIMIT 3` returns rows with non-null values (SUM-06)
- [ ] Deployment returns to `0/0` replicas after ~5 min of idle (SUM-10)

**Tests**: none (manual smoke test)
**Gate**: Job — manual verification per checklist above

**Commit**: none (verification-only task)

---

## Requirement Traceability

| Requirement | Task(s) |
|-------------|---------|
| SUM-01 PDF page-range extraction | T5 |
| SUM-02 Per-doc text extraction (pypdf) | T5 |
| SUM-03 OpenAI classification + resumo | T5 |
| SUM-04 Structured resumo per tipo template | T5 |
| SUM-05 Lance table schema (10 cols) | T5 |
| SUM-06 Trino GCS path accessibility | T5 (lancedb.connect URI), T9 (Trino SELECT validates auto-discovery) |
| SUM-07 all-MiniLM-L6-v2 384-d embeddings | T5 |
| SUM-08 IVF_PQ index on resumo_embedding | T5 |
| SUM-09 FTS index on resumo | T5 |
| SUM-10 KEDA ScaledObject (min=0, max=5) | T8 |
| SUM-11 Idempotency: skip existing doc_id | T5 |
| SUM-12 Pull subscription cases-summarizer-sub | T2 |
| SUM-13 Structured logging | T5 |
| SUM-14 OpenAI key via K8s Secret | T7 |
| SUM-15 Terraform module modules/cases-summarizer/ | T2, T4 |
| SUM-16 KEDA Helm module + var.keda flag | T1, T4 |
| SUM-17 resumo template per tipo_documento (4 types) | T5 |
| SUM-01–SUM-13, SUM-06 (P1 + P2 functional) | T9 (smoke test validates all) |
