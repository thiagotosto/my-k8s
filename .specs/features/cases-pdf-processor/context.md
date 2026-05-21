# cases-pdf-processor Context

**Gathered:** 2026-05-21
**Spec:** `.specs/features/cases-pdf-processor/spec.md`
**Status:** Ready for design

---

## Feature Boundary

Two-function fan-out pipeline: Function 1 builds the doc_id index and publishes to
Pub/Sub; Function 2 converts each doc_id to markdown independently and in parallel.
No changes to the output GCS path or the Docling conversion logic.

---

## Implementation Decisions

### PDF access in Function 2

Function 2 re-downloads the full source PDF from GCS on each invocation, using
`bucket` and `file_path` from the Pub/Sub message. No page pre-staging by Function 1.

### Idempotency

Only Function 2 checks idempotency — before converting, it checks whether
`gs://justeam/raw/cases_md/<file_name_stem>/<doc_id>.md` already exists and exits
early if so. Function 1 always publishes all doc_id messages on every invocation.

### Concurrency and scale

Function 2: `concurrency=1` (one Docling conversion per instance),
`max_instance_count = var.max_converter_instances` (default `10`). The variable must
be exposed in Terraform so it can be changed without a code change.

### Infrastructure scope

All resources (both functions, Pub/Sub topic + subscription, both service accounts,
all IAM bindings, the new variable) live in the same Terraform module as the existing
cases-pdf-processor infra.

---

## Specific References

- None — no external product references. Standard Cloud Functions 2nd gen + Pub/Sub
  Eventarc trigger pattern.

---

## Deferred Ideas

- None — discussion stayed within feature scope.
