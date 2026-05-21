# cases-pdf-processor — Design

## Architecture

```
GCS (justeam/raw/cases_pdf/*.pdf)
  │  [object.finalized Eventarc trigger]
  ▼
cases-pdf-indexer  (Cloud Run v2)
  │  pypdf + regex → doc_id → {min_page, max_page}
  │  N messages published
  ▼
Pub/Sub topic: cases-pdf-doc-events
  │  [messagePublished Eventarc trigger, up to N parallel]
  ▼
cases-pdf-converter ×N  (Cloud Run v2, concurrency=1)
  │  idempotency check → GCS head
  │  GCS download → Docling → markdown
  ▼
GCS (justeam/raw/cases_md/<file_stem>/<doc_id>.md)
```

## Deployment Strategy

Both functions deploy as **Cloud Run v2 services** with custom Docker images built via
`null_resource` → `docker build/push` to dedicated Artifact Registry repos. This is the
same pattern used by `apps/spark/image.tf`.

| | Indexer | Converter |
|---|---|---|
| AR repo | `cases-pdf-indexer` (created in module) | `cases-pdf-converter` (created in module) |
| Image URL | `{region}-docker.pkg.dev/{project}/cases-pdf-indexer/image:latest` | `{region}-docker.pkg.dev/{project}/cases-pdf-converter/image:latest` |
| Base image | `python:3.13-slim` | `python:3.13-slim` |
| Model pre-load | No (lightweight deps only) | Yes — Docling models baked into image at build time |
| Trigger | Eventarc GCS `object.finalized` | Eventarc Pub/Sub `messagePublished` |
| Memory / CPU | 512Mi / 1 | 4Gi / 2 |
| Timeout | 300s | 3600s |
| Max instances | 1 | `var.max_converter_instances` (default 10) |
| Concurrency | 1 | 1 |

The converter's cold start is ~5–10s (container pull + process start) instead of 2–3 min
(model download), because models are baked into the image layer during `docker build`.

## Terraform Placement

`modules/cases-pdf-processor/` called from root `main.tf`, consistent with
`module "trino"` and `module "spark-operator"`. All resources (AR repos, Pub/Sub, IAM,
image builds, Cloud Run services, Eventarc triggers) live in this one module.

Root `main.tf` addition:
```hcl
module "cases_pdf_processor" {
  count      = var.cases_pdf_processor ? 1 : 0
  source     = "./modules/cases-pdf-processor"
  project_id = data.google_project.default.project_id
  region     = var.gcp_region
}
```

Root `variables.tf` addition:
```hcl
variable "cases_pdf_processor" { type = bool; default = true }
```

## Module File Structure

```
modules/cases-pdf-processor/
├── main.tf            # All Terraform resources
├── variables.tf       # max_converter_instances, region, project_id
├── outputs.tf         # service URIs (informational)
└── src/
    ├── indexer/
    │   ├── Dockerfile
    │   ├── main.py          # REQ-001 through REQ-009
    │   └── requirements.txt
    └── converter/
        ├── Dockerfile       # Pre-downloads Docling models
        ├── main.py          # REQ-010 through REQ-013
        └── requirements.txt
```

## Terraform Resources

### Artifact Registry

```hcl
resource "google_artifact_registry_repository" "indexer" {
  location      = var.region
  repository_id = "cases-pdf-indexer"
  format        = "DOCKER"
}

resource "google_artifact_registry_repository" "converter" {
  location      = var.region
  repository_id = "cases-pdf-converter"
  format        = "DOCKER"
}
```

Locals:
```hcl
locals {
  indexer_image   = "${var.region}-docker.pkg.dev/${var.project_id}/cases-pdf-indexer/image:latest"
  converter_image = "${var.region}-docker.pkg.dev/${var.project_id}/cases-pdf-converter/image:latest"
}
```

### Pub/Sub

- `google_pubsub_topic.cases_pdf_doc_events` — id: `cases-pdf-doc-events`
- `google_pubsub_subscription.cases_pdf_doc_events_sub` — id: `cases-pdf-doc-events-sub`, ack deadline 600s

### Service Accounts

- `google_service_account.indexer` — account_id: `cases-pdf-indexer`
- `google_service_account.converter` — account_id: `cases-pdf-converter`

### IAM — Indexer SA

| Role | Resource |
|------|----------|
| `roles/storage.objectViewer` | `justeam` bucket, condition: prefix `raw/cases_pdf/` |
| `roles/pubsub.publisher` | `cases-pdf-doc-events` topic |
| `roles/eventarc.eventReceiver` | project-level |
| `roles/run.invoker` | project-level |

### IAM — Converter SA

| Role | Resource |
|------|----------|
| `roles/storage.objectViewer` | `justeam` bucket, condition: prefix `raw/cases_pdf/` |
| `roles/storage.objectCreator` | `justeam` bucket, condition: prefix `raw/cases_md/` |
| `roles/pubsub.subscriber` | `cases-pdf-doc-events-sub` subscription |
| `roles/eventarc.eventReceiver` | project-level |
| `roles/run.invoker` | project-level |

### IAM — Eventarc Agents (required for triggers to fire)

```hcl
# Enables GCS → Eventarc trigger
resource "google_project_iam_member" "gcs_sa_pubsub_publisher" {
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${var.project_number}@gs-project-accounts.iam.gserviceaccount.com"
}

# Enables Pub/Sub → Eventarc → Cloud Run token auth
resource "google_project_iam_member" "pubsub_sa_token_creator" {
  role   = "roles/iam.serviceAccountTokenCreator"
  member = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}
```

(`var.project_number` passed from root via `data.google_project.default.number`)

### Image Builds

```hcl
resource "null_resource" "indexer_image" {
  triggers = {
    dockerfile = filemd5("${path.module}/src/indexer/Dockerfile")
    main_py    = filemd5("${path.module}/src/indexer/main.py")
  }
  provisioner "local-exec" {
    command = "docker build -t ${local.indexer_image} ${path.module}/src/indexer && docker push ${local.indexer_image}"
  }
  depends_on = [google_artifact_registry_repository.indexer]
}
```

Same pattern for `null_resource.converter_image`.

### Cloud Run Services

**Indexer:**
```hcl
resource "google_cloud_run_v2_service" "indexer" {
  name     = "cases-pdf-indexer"
  location = var.region
  template {
    service_account              = google_service_account.indexer.email
    max_instance_request_concurrency = 1
    timeout                      = "300s"
    scaling { min_instance_count = 0; max_instance_count = 1 }
    containers {
      image = local.indexer_image
      env { name = "PUBSUB_TOPIC"; value = google_pubsub_topic.cases_pdf_doc_events.id }
      resources { limits = { memory = "512Mi"; cpu = "1" } }
    }
  }
  depends_on = [null_resource.indexer_image]
}
```

**Converter:**
```hcl
resource "google_cloud_run_v2_service" "converter" {
  name     = "cases-pdf-converter"
  location = var.region
  template {
    service_account              = google_service_account.converter.email
    max_instance_request_concurrency = 1
    timeout                      = "3600s"
    scaling { min_instance_count = 0; max_instance_count = var.max_converter_instances }
    containers {
      image = local.converter_image
      resources { limits = { memory = "4Gi"; cpu = "2" } }
    }
  }
  depends_on = [null_resource.converter_image]
}
```

### Eventarc Triggers

**Indexer (GCS finalized):**
```hcl
resource "google_eventarc_trigger" "indexer" {
  name     = "cases-pdf-indexer-trigger"
  location = var.region
  matching_criteria { attribute = "type";    value = "google.cloud.storage.object.v1.finalized" }
  matching_criteria { attribute = "bucket";  value = "justeam" }
  matching_criteria { attribute = "subject"; value = "objects/raw/cases_pdf/**"; operator = "match-path-pattern" }
  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.indexer.name
      region  = var.region
    }
  }
  service_account = google_service_account.indexer.email
}
```

**Converter (Pub/Sub messagePublished):**
```hcl
resource "google_eventarc_trigger" "converter" {
  name     = "cases-pdf-converter-trigger"
  location = var.region
  matching_criteria { attribute = "type"; value = "google.cloud.pubsub.topic.v1.messagePublished" }
  transport { pubsub { topic = google_pubsub_topic.cases_pdf_doc_events.id } }
  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.converter.name
      region  = var.region
    }
  }
  service_account = google_service_account.converter.email
}
```

## Python Source

### `src/indexer/Dockerfile`

```dockerfile
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
CMD ["functions-framework", "--target=cases_pdf_indexer", "--port=8080"]
```

### `src/indexer/requirements.txt`

```
functions-framework==3.*
google-cloud-storage
google-cloud-pubsub
pypdf
```

### `src/indexer/main.py` (REQ-001 to REQ-009)

- `@functions_framework.cloud_event` handler
- Extracts `bucket` + `name` from `cloud_event.data`
- Downloads PDF to `/tmp` via `google.cloud.storage.Client`
- Iterates `PdfReader` pages, matches `r"Num. ([1-9][0-9]*) - Pág. ([1-9][0-9]*)"`, builds `{doc_id: {min_page, max_page}}` (1-based page numbers, same logic as `processo.ipynb`)
- Publishes one JSON message per doc_id to `os.environ["PUBSUB_TOPIC"]`; payload: `{doc_id, min_page, max_page, bucket, file_path}`

### `src/converter/Dockerfile`

```dockerfile
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# Bake Docling ML models into image — eliminates cold-start model download
RUN python -c "from docling.document_converter import DocumentConverter; \
               from docling.datamodel.base_models import InputFormat; \
               DocumentConverter(allowed_formats=[InputFormat.PDF])"
COPY main.py .
CMD ["functions-framework", "--target=cases_pdf_converter", "--port=8080"]
```

### `src/converter/requirements.txt`

```
functions-framework==3.*
google-cloud-storage
docling
```

### `src/converter/main.py` (REQ-010 to REQ-013)

- `@functions_framework.cloud_event` handler
- Base64-decodes `cloud_event.data["message"]["data"]`, parses JSON → `{doc_id, min_page, max_page, bucket, file_path}`
- Idempotency check: `storage.Client().bucket("justeam").blob(f"raw/cases_md/{Path(file_path).stem}/{doc_id}.md").exists()` → return if true
- Downloads full source PDF from GCS to `/tmp`
- Converts: `DocumentConverter(allowed_formats=[InputFormat.PDF]).convert(source=tmp_path, page_range=(min_page, max_page)).document.export_to_markdown()`
- Uploads markdown to `gs://justeam/raw/cases_md/<file_stem>/<doc_id>.md`

## Reference

- Prototype: `apps/playground/processo.ipynb`
- Existing image build pattern: `apps/spark/image.tf` (`null_resource` + `docker build/push`)
- Existing GCP module pattern: `modules/gcs-bucket/`, `modules/trino/`
- GCS IAM condition reference: root `main.tf` (`google_project_iam_member.workloads_gcs`)
