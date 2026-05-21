# cases-pdf-processor

## Overview

Two-function pipeline that processes multi-case legal PDFs from GCS using docling,
exporting one markdown file per legal case (`doc_id`) to GCS.

Each PDF in the source bucket may contain multiple legal cases. Pages are identified
by embedded metadata (`Num. X - Pág. Y`) that maps each page to its case.

**Function 1 — cases-pdf-indexer (Eventarc, GCS trigger):**
Downloads the PDF, builds the `doc_id → {min_page, max_page}` index, and publishes
one Pub/Sub message per doc_id. Terminates after publishing.

**Function 2 — cases-pdf-converter (Eventarc, Pub/Sub trigger):**
Receives one message per doc_id, re-downloads the full PDF from GCS, converts the
relevant page range to markdown via Docling, and uploads the result to GCS. Up to
`max_converter_instances` run in parallel, each handling one doc_id at a time.

## Triggers

| Function | Type | Source |
|---|---|---|
| cases-pdf-indexer | Eventarc — `google.cloud.storage.object.v1.finalized` | `gs://justeam/raw/cases_pdf` |
| cases-pdf-converter | Eventarc — Pub/Sub topic `cases-pdf-doc-events` | One message per doc_id published by Function 1 |

## Requirements

---

### Function 1 — cases-pdf-indexer

---

### REQ-001 — CloudEvent handler

Function 1 is implemented as a CloudEvent handler using `functions-framework`
(`@functions_framework.cloud_event` decorator).

**Acceptance:** Function signature matches the CloudEvent spec and is deployable via
`google_cloudfunctions2_function` Terraform resource.

---

### REQ-002 — Event parsing

Extracts GCS `bucket` and object `name` from the CloudEvent attributes.

**Acceptance:** Correctly parses both fields from the event data for any valid
`google.cloud.storage.object.v1.finalized` event.

---

### REQ-003 — PDF download

Downloads the PDF from GCS to local ephemeral storage (`/tmp`).

**Acceptance:** PDF file is accessible on the local filesystem before processing begins.

---

### REQ-004 — Page indexing by doc_id

Indexes PDF pages by `doc_id` using `pypdf` and the regex pattern:

```
Num. ([1-9][0-9]*) - Pág. ([1-9][0-9]*)
```

Produces a mapping of `doc_id → {min_page, max_page}` (1-based page numbers).

**Acceptance:** Output mapping matches the logic in `apps/playground/processo.ipynb`
(cells: `PdfReader` loop → `groupby("idx").agg(min_page, max_page)`).

---

### REQ-009 — Pub/Sub publish per doc_id

After building the index, Function 1 publishes one message to the Pub/Sub topic
`cases-pdf-doc-events` for each `doc_id` found. Message payload (JSON):

```json
{
  "doc_id": "<doc_id>",
  "min_page": <int>,
  "max_page": <int>,
  "bucket": "<source bucket>",
  "file_path": "<GCS object name>"
}
```

**Acceptance:** For a PDF with N doc_ids, exactly N messages are published. Each
message contains all five fields with correct values.

---

### Function 2 — cases-pdf-converter

---

### REQ-010 — Pub/Sub CloudEvent handler

Function 2 is implemented as a CloudEvent handler triggered by Eventarc listening
to the `cases-pdf-doc-events` Pub/Sub topic. Parses the base64-decoded JSON message
payload to extract `{doc_id, min_page, max_page, bucket, file_path}`.

**Acceptance:** Function receives and correctly parses messages published by REQ-009.

---

### REQ-011 — Idempotency

Before processing, checks if the output file already exists in GCS:

```
gs://justeam/raw/cases_md/<file_name_stem>/<doc_id>.md
```

If the object exists, the function exits successfully without conversion.

**Acceptance:** Re-delivery of the same Pub/Sub message does not overwrite existing
output. GCS object count stays constant on re-runs.

---

### REQ-012 — PDF download

Downloads the full source PDF from GCS to local ephemeral storage (`/tmp`) using
`bucket` and `file_path` from the Pub/Sub message.

**Acceptance:** PDF file is accessible on the local filesystem before Docling runs.

---

### REQ-013 — Docling conversion and markdown upload

Converts the `doc_id`'s page range to markdown and uploads the result to GCS:

```python
DocumentConverter(allowed_formats=[InputFormat.PDF])
    .convert(source=local_pdf_path, page_range=(min_page, max_page))
    .document
    .export_to_markdown()
```

Output path: `gs://justeam/raw/cases_md/<file_name_stem>/<doc_id>.md`

Where `<file_name_stem>` is the stem of `file_path`
(e.g. `raw/cases_pdf/batch_2026-05-20.pdf` → `batch_2026-05-20`).

**Acceptance:** GCS object exists at the expected path after the function completes.
Markdown output is non-empty and structurally valid.

---

### REQ-008 — Infrastructure provisioning via Terraform

Deployed in a single Terraform module with:

**Function 1 — cases-pdf-indexer:**
- Dedicated GCP service account
- `roles/storage.objectViewer` on `justeam` bucket (prefix `raw/cases_pdf/`)
- `roles/pubsub.publisher` on topic `cases-pdf-doc-events`
- Eventarc trigger: `google.cloud.storage.object.v1.finalized` on `justeam`, path filter `raw/cases_pdf/**`

**Function 2 — cases-pdf-converter:**
- Dedicated GCP service account
- `roles/storage.objectViewer` on `justeam` bucket (prefix `raw/cases_pdf/`)
- `roles/storage.objectCreator` on `justeam` bucket (prefix `raw/cases_md/`)
- `roles/pubsub.subscriber` on subscription `cases-pdf-doc-events-sub`
- Eventarc trigger: Pub/Sub topic `cases-pdf-doc-events`
- `concurrency = 1`
- `max_instance_count = var.max_converter_instances` (default: `10`)

**Shared:**
- Pub/Sub topic: `cases-pdf-doc-events`
- Pub/Sub subscription: `cases-pdf-doc-events-sub`
- Variable `max_converter_instances` (number, default `10`)

**Acceptance:** `terraform plan` on the module creates all of the above resources
with no errors.

---

## Reference

- Prototype: `apps/playground/processo.ipynb`
- Existing GCS IAM pattern: `modules/gcs-bucket/`
- Existing GCP provider config: `main.tf` (root)

## Out of scope

- Hierarchical text structuring or LanceDB vector storage (notebook phases 3–4)
- Batch reprocessing of previously uploaded PDFs
- Downstream notifications or triggers after converter upload
