# cases-pdf-processor — Tasks

**Spec:** `spec.md` | **Design:** `design.md` | **Context:** `context.md`

## Dependency Graph

```
T1 (scaffold)
├── T2 (pub/sub) ──────────── T5 (AR + SAs + IAM)
├── T3 (indexer src) ──[P]──┤   ├── T6 (indexer image build) ─[P]─ T8 (indexer CR + trigger)
└── T4 (converter src) ─[P]─┘   └── T7 (converter image build) ─[P]─ T9 (converter CR + trigger)
                                                                      └── T10 (terraform plan gate)
```

[P] = can run in parallel with sibling tasks

---

## T1 — Module scaffold + root wiring ✅ COMPLETED

**What:** Create the module directory and stub files; wire into root workspace.

**Where:**
- Create `modules/cases-pdf-processor/main.tf` (empty stub with `terraform {}` block)
- Create `modules/cases-pdf-processor/variables.tf` (vars: `project_id`, `project_number`, `region`, `max_converter_instances`)
- Create `modules/cases-pdf-processor/outputs.tf` (empty stub)
- Edit `variables.tf` (root) — add `variable "cases_pdf_processor" { type = bool; default = true }`
- Edit `main.tf` (root) — add `module "cases_pdf_processor"` call (see design.md)

**Done when:** `terraform init` succeeds on root workspace; `terraform validate` passes.

**Gate:** `terraform validate` → no errors.

---

## T2 — Pub/Sub resources ✅ COMPLETED

**Depends on:** T1
**Parallel with:** T3, T4

**What:** Add Pub/Sub topic and subscription to `modules/cases-pdf-processor/main.tf`.

**Where:** `modules/cases-pdf-processor/main.tf`

**Resources:**
- `google_pubsub_topic.cases_pdf_doc_events` — name: `cases-pdf-doc-events`
- `google_pubsub_subscription.cases_pdf_doc_events_sub` — name: `cases-pdf-doc-events-sub`, `ack_deadline_seconds = 600`

**Done when:** `terraform plan` shows 2 new Pub/Sub resources.

**Gate:** `terraform plan` → `Plan: 2 to add`.

---

## T3 — Indexer source files ✅ COMPLETED

**Depends on:** T1
**Parallel with:** T2, T4

**What:** Write the indexer Python source and Dockerfile.

**Where:**
- Create `modules/cases-pdf-processor/src/indexer/Dockerfile`
- Create `modules/cases-pdf-processor/src/indexer/requirements.txt`
- Create `modules/cases-pdf-processor/src/indexer/main.py`

**Reqs covered:** REQ-001, REQ-002, REQ-003, REQ-004, REQ-009

**Done when:** `main.py` implements the full CloudEvent handler — parses GCS event, downloads PDF, builds `{doc_id: {min_page, max_page}}` index via pypdf regex, publishes one Pub/Sub message per doc_id. Matches prototype logic in `processo.ipynb`.

**Gate:** Static review — no syntax errors (`python -m py_compile main.py`).

---

## T4 — Converter source files ✅ COMPLETED

**Depends on:** T1
**Parallel with:** T2, T3

**What:** Write the converter Python source and Dockerfile (with model pre-bake).

**Where:**
- Create `modules/cases-pdf-processor/src/converter/Dockerfile`
- Create `modules/cases-pdf-processor/src/converter/requirements.txt`
- Create `modules/cases-pdf-processor/src/converter/main.py`

**Reqs covered:** REQ-010, REQ-011, REQ-012, REQ-013

**Done when:** `main.py` implements the full CloudEvent handler — parses Pub/Sub message, checks idempotency via GCS head, downloads source PDF, runs Docling page-range conversion, uploads markdown. Dockerfile pre-downloads Docling models at build time via `RUN python -c "DocumentConverter(...)"`.

**Gate:** Static review — no syntax errors (`python -m py_compile main.py`).

---

## T5 — Artifact Registry repos + service accounts + IAM ✅ COMPLETED

**Depends on:** T2
**Parallel with:** T3, T4 (once T2 completes)

**What:** Add AR repos, service accounts, and all IAM bindings to `main.tf`.

**Where:** `modules/cases-pdf-processor/main.tf`

**Resources:**
- `google_artifact_registry_repository.indexer` — id: `cases-pdf-indexer`
- `google_artifact_registry_repository.converter` — id: `cases-pdf-converter`
- `google_service_account.indexer` — account_id: `cases-pdf-indexer`
- `google_service_account.converter` — account_id: `cases-pdf-converter`
- IAM bindings per design.md (indexer: storage viewer + pubsub publisher + eventarc receiver + run invoker; converter: storage viewer + storage creator + pubsub subscriber + eventarc receiver + run invoker)
- Eventarc agent IAM: GCS SA → `roles/pubsub.publisher`; Pub/Sub SA → `roles/iam.serviceAccountTokenCreator`

**Done when:** `terraform plan` shows all AR repos, SAs, and IAM resources with no errors.

**Gate:** `terraform plan` → no errors; IAM resource count matches design.md.

---

## T6 — Indexer image build ✅ COMPLETED

**Depends on:** T3, T5
**Parallel with:** T7

**What:** Add `null_resource.indexer_image` to trigger `docker build/push` for the indexer image.

**Where:** `modules/cases-pdf-processor/main.tf`

**Details:**
- Locals: `indexer_image = "${var.region}-docker.pkg.dev/${var.project_id}/cases-pdf-indexer/image:latest"`
- `triggers` on `filemd5` of `Dockerfile` and `main.py`
- `depends_on = [google_artifact_registry_repository.indexer]`

**Done when:** `terraform plan` shows the null_resource; on `terraform apply` the image is pushed to AR successfully.

**Gate:** `terraform plan` → null_resource present; `gcloud artifacts docker images list` shows image after apply.

---

## T7 — Converter image build ✅ COMPLETED

**Depends on:** T4, T5
**Parallel with:** T6

**What:** Add `null_resource.converter_image` to trigger `docker build/push` for the converter image.

**Where:** `modules/cases-pdf-processor/main.tf`

**Details:**
- Locals: `converter_image = "${var.region}-docker.pkg.dev/${var.project_id}/cases-pdf-converter/image:latest"`
- `triggers` on `filemd5` of `Dockerfile` and `main.py`
- `depends_on = [google_artifact_registry_repository.converter]`
- Note: `docker build` will execute the `RUN python -c "DocumentConverter(...)"` layer — expect several minutes on first build.

**Done when:** `terraform plan` shows the null_resource; on `terraform apply` the image (with baked models) is pushed to AR successfully.

**Gate:** `terraform plan` → null_resource present; `gcloud artifacts docker images list` shows image after apply.

---

## T8 — Indexer Cloud Run service + GCS Eventarc trigger ✅ COMPLETED

**Depends on:** T5, T6
**Parallel with:** T9

**What:** Add `google_cloud_run_v2_service.indexer` and `google_eventarc_trigger.indexer`.

**Where:** `modules/cases-pdf-processor/main.tf`

**Spec refs:** REQ-001, REQ-008

**Done when:** `terraform plan` shows the Cloud Run service (512Mi/1cpu, timeout 300s, max 1 instance) and Eventarc trigger with GCS filter `objects/raw/cases_pdf/**`.

**Gate:** `terraform plan` → Cloud Run service + Eventarc trigger resources present, no errors.

---

## T9 — Converter Cloud Run service + Pub/Sub Eventarc trigger ✅ COMPLETED

**Depends on:** T5, T7
**Parallel with:** T8

**What:** Add `google_cloud_run_v2_service.converter` and `google_eventarc_trigger.converter`.

**Where:** `modules/cases-pdf-processor/main.tf`

**Spec refs:** REQ-008, REQ-010

**Done when:** `terraform plan` shows the Cloud Run service (4Gi/2cpu, timeout 3600s, concurrency=1, max `var.max_converter_instances` instances) and Eventarc trigger connected to `cases-pdf-doc-events` topic.

**Gate:** `terraform plan` → Cloud Run service + Eventarc trigger resources present, no errors.

---

## T10 — Full terraform plan gate ✅ COMPLETED

**Depends on:** T8, T9

**What:** Run a clean `terraform plan` on the root workspace with `cases_pdf_processor=true` and verify all expected resources are present.

**Where:** Root workspace

**Done when:** Plan output shows:
- 2 Artifact Registry repositories
- 2 Pub/Sub resources (topic + subscription)
- 2 service accounts + ≥8 IAM member bindings
- 2 null_resources (image builds)
- 2 Cloud Run v2 services
- 2 Eventarc triggers
- 0 errors, 0 unexpected destroy/recreate

**Gate:** `terraform plan -var="cases_pdf_processor=true"` exits 0 with expected resource counts.

---

## Traceability

| Req | Task(s) |
|-----|---------|
| REQ-001 | T3, T8 |
| REQ-002 | T3 |
| REQ-003 | T3 |
| REQ-004 | T3 |
| REQ-009 | T3 |
| REQ-010 | T4, T9 |
| REQ-011 | T4 |
| REQ-012 | T4 |
| REQ-013 | T4 |
| REQ-008 | T2, T5, T6, T7, T8, T9 |
