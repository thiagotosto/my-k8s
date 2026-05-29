# Feature: refactor-hierarquical-cases-to-markdown

## Context

The `hierarquical-cases` Spark job previously downloaded raw PDFs from GCS and ran Docling in-process to convert them. The `cases-pdf-processor` Cloud Run pipeline now handles that conversion upstream, writing one Docling-rendered markdown file per legal case to `gs://justeam/raw/cases_md/{file_stem}/{doc_id}.md`.

This feature refactors the Spark job to consume those pre-converted markdown files, reducing job resource requirements and removing the Docling dependency from the Docker image.

## Requirements

### REQ-001 — New connector: GCSMarkdownSource

**File:** `apps/spark/lib/spark_etl/connectors/gcs_markdown_source.py`

Options:
- `bucket: str`
- `prefix: str` — GCS prefix, e.g. `"raw/cases_md/"`

Behavior:
1. List all blobs under `gs://{bucket}/{prefix}`
2. For each blob ending in `.md` at path `{prefix}{file_stem}/{doc_id}.md`:
   - Skip if `doc_id` part is not numeric
   - `download_as_text()` the content
3. Return `spark.createDataFrame(rows, schema)` with explicit schema

Output schema:

| Column    | Type   |
|-----------|--------|
| doc_id    | long   |
| file_stem | string |
| content   | string |
| gcs_path  | string |

### REQ-002 — Export from connectors package

Add `GCSMarkdownSource` and `GCSMarkdownSourceOptions` to `connectors/__init__.py` and `__all__`.

### REQ-003 — Chunked transform: heading-based section splitting

**Function:** `chunk_markdown(df: DataFrame) -> DataFrame`

Chunking logic (driver-side after `df.collect()`):
- Parse headings with regex `^(#{1,6})\s+(.+)` (MULTILINE)
- Each chunk = heading + following body text (stripped)
- Skip chunks with empty body
- Fallback: if no headings found, emit one chunk with `section=""`, `heading_level=0`

Output schema of chunks table:

| Column          | Type          | Notes                             |
|-----------------|---------------|-----------------------------------|
| chunk_id        | string        | `"{doc_id}_{chunk_index}"`        |
| doc_id          | long          |                                   |
| file_stem       | string        |                                   |
| section         | string        | Heading text                      |
| heading_level   | integer       | 1–6, or 0 for no-heading fallback |
| chunk_index     | integer       | Ordinal within doc                |
| text            | string        | Body text                         |
| embedding_model | string        | Literal `"all-MiniLM-L6-v2"`     |
| text_embedding  | array\<float\>| 384d, cosine-normalized           |

Embeddings generated via `encode_text` pandas UDF (sentence-transformers `all-MiniLM-L6-v2`).

### REQ-004 — Refactor hierarquical-cases/job.py

- Replace `GCSLegalCasePDFSource` + `transform_legal_cases` (Docling) with `GCSMarkdownSource` + `chunk_markdown`
- Env vars: `GCS_BUCKET` + `GCS_MD_PREFIX` (replaces `GCS_PDF_PATH`)
- Lance table: `sandbox.default.cases_chunks` (renamed from `hierarquical_cases`)
- Indexes unchanged: `VectorIndexSpec(IVF_PQ, text_embedding, dim=384, partitions=4, sub_vecs=12)` + `FTSIndexSpec(text)`

### REQ-005 — Update spark.yaml

Driver env changes:
- Remove `GCS_PDF_PATH`, `DOCLING_CACHE_DIR`
- Add `GCS_MD_PREFIX: raw/cases_md/`

### REQ-006 — Remove docling from Dockerfile

Delete `RUN pip install … docling` layer from `apps/spark/Dockerfile`.
No job uses Docling after this change. Keep `pypdf` (used by `GCSLegalCasePDFSource`).

### REQ-007 — Unit tests

**File:** `apps/spark/lib/tests/connectors/test_gcs_markdown_source.py`

Tests:
- `test_options_valid`
- `test_options_missing_bucket_raises`
- `test_options_missing_prefix_raises`
- `test_read_parses_doc_id_and_file_stem` — path `raw/cases_md/thiago_x_meli/42.md` → `doc_id=42`, `file_stem="thiago_x_meli"`
- `test_read_skips_non_md_files`
- `test_read_lists_blobs_and_creates_dataframe`
- `test_type_guard_rejects_dict`

Gate: `cd apps/spark/lib && uv run pytest tests/ -v` — all tests pass

## Verification

1. `cd apps/spark/lib && uv run pytest tests/ -v` — expect ~48 tests passing
2. `python -c "from spark_etl.connectors import GCSMarkdownSource, GCSMarkdownSourceOptions"` — no error
3. `spark.yaml` — confirm `GCS_PDF_PATH` and `DOCLING_CACHE_DIR` absent, `GCS_MD_PREFIX` present
4. `Dockerfile` — confirm `docling` layer removed
