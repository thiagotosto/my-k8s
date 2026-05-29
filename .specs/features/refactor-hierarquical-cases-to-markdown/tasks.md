# Tasks: refactor-hierarquical-cases-to-markdown

## T1 — Add GCSMarkdownSource connector

**What:** Create `apps/spark/lib/spark_etl/connectors/gcs_markdown_source.py`  
**Where:** `spark_etl/connectors/`  
**Reuses:** `DataSource` ABC from `source.py`; same GCS client pattern as `gcs_legal_case_pdf_source.py`  
**Done when:**
- `GCSMarkdownSourceOptions(bucket, prefix)` validated by Pydantic
- `read()` lists blobs, filters `.md`, parses `file_stem` / `doc_id` from path, downloads text
- Returns DataFrame with explicit schema: `doc_id (long), file_stem, content, gcs_path (string)`
- Non-numeric `doc_id` filenames silently skipped
- Empty corpus returns empty DataFrame with correct schema (not a schema-inference error)

---

## T2 — Export GCSMarkdownSource from connectors package

**What:** Add import + `__all__` entry in `apps/spark/lib/spark_etl/connectors/__init__.py`  
**Depends on:** T1  
**Done when:** `from spark_etl.connectors import GCSMarkdownSource, GCSMarkdownSourceOptions` succeeds

---

## T3 — Unit tests for GCSMarkdownSource

**What:** Create `apps/spark/lib/tests/connectors/test_gcs_markdown_source.py`  
**Depends on:** T1  
**Reuses:** Mock pattern from `test_gcs_legal_case_pdf_source.py` (`patch.dict(sys.modules, ...)`)  
**Tests:**
- `test_options_valid`
- `test_options_missing_bucket_raises`
- `test_options_missing_prefix_raises`
- `test_read_parses_doc_id_and_file_stem` — `raw/cases_md/thiago_x_meli/42.md` → `doc_id=42`, `file_stem="thiago_x_meli"`
- `test_read_skips_non_md_files` — `.pdf` blob alongside `.md` → only 1 row
- `test_read_lists_blobs_and_creates_dataframe` — verifies GCS client called with correct bucket+prefix
- `test_type_guard_rejects_dict`

**Gate:** `cd apps/spark/lib && uv run pytest tests/connectors/test_gcs_markdown_source.py -v` — 7 passed

---

## T4 — Refactor job.py

**What:** Rewrite `apps/spark/jobs/hierarquical-cases/job.py`  
**Depends on:** T2  
**Done when:**
- Imports `GCSMarkdownSource`, `GCSMarkdownSourceOptions` (remove `GCSLegalCasePDFSource`, `GCSLegalCasePDFOptions`)
- Remove `transform_legal_cases` and all `docling` imports
- Add `chunk_markdown(df)`:
  - `df.collect()` → iterate rows
  - Per row: `re.finditer(r'^(#{1,6})\s+(.+)', content, re.MULTILINE)` to split sections
  - Each chunk: `chunk_id="{doc_id}_{chunk_index}"`, `heading_level=len(match.group(1))`, `section`, `text` (body between headings, stripped)
  - Skip chunks with empty body
  - Fallback: no headings → one chunk with `section=""`, `heading_level=0`
  - After `createDataFrame`: `withColumn("text_embedding", encode_text(col("text")))` + `.cache()` + `.count()`
  - `embedding_model` written as `F.lit("all-MiniLM-L6-v2")` column
- `main()` reads `GCS_BUCKET` + `GCS_MD_PREFIX` env vars; `table_name="cases_chunks"`
- Remove `Window`, `pyspark.sql.window` import (no longer needed)

---

## T5 — Update spark.yaml env vars

**What:** Edit `apps/spark/jobs/hierarquical-cases/spark.yaml`  
**Done when:**
- Driver env: `GCS_PDF_PATH` removed, `DOCLING_CACHE_DIR` removed, `GCS_MD_PREFIX: raw/cases_md/` added
- Executor env unchanged (no PDF/Docling vars were there)

---

## T6 — Remove docling from Dockerfile

**What:** Delete the `RUN pip install … docling` layer from `apps/spark/Dockerfile`  
**Done when:**
- Layer removed; `libgl1`/`libglib2.0-0` and `pypdf` remain
- `image.tf` will trigger rebuild on next `terraform apply` (no change needed there)

---

## T7 — Full test suite gate

**What:** Verify all existing tests still pass after T1–T6  
**Depends on:** T1–T4  
**Gate:** `cd apps/spark/lib && uv run pytest tests/ -v` — 48 passed (41 existing + 7 new)

---

## T8 — E2E smoke test: job runs and table is queryable via Trino

**What:** Submit the SparkApplication, wait for completion, verify table schema and data via Trino  
**Depends on:** T4, T5, T6 (and a running GKE cluster with Trino deployed)

**Steps:**

1. **Submit job**
   ```bash
   kubectl apply -f apps/spark/jobs/hierarquical-cases/spark.yaml -n spark-jobs
   ```

2. **Wait for completion**
   ```bash
   kubectl get sparkapplication hierarquical-cases -n spark-jobs -w
   # expect phase: Completed
   ```

3. **Verify table exists in GCS**
   ```bash
   gsutil ls gs://justeam/sandbox/ | grep cases_chunks
   ```

4. **Verify schema via Trino**
   ```sql
   DESCRIBE sandbox.default.cases_chunks;
   ```
   Expected columns: `chunk_id, doc_id, file_stem, section, heading_level, chunk_index, text, embedding_model, text_embedding`

5. **Verify data and embedding model label**
   ```sql
   SELECT embedding_model, count(*) AS chunks
   FROM sandbox.default.cases_chunks
   GROUP BY embedding_model;
   ```
   Expected: one row with `embedding_model = 'all-MiniLM-L6-v2'`, `chunks > 0`

6. **Spot-check a chunk**
   ```sql
   SELECT chunk_id, doc_id, file_stem, section, heading_level, length(text) AS text_len
   FROM sandbox.default.cases_chunks
   LIMIT 5;
   ```
   Expected: `heading_level` in 1–6 (or 0 for fallback), `text_len > 0`, `file_stem` matches a known PDF stem

7. **Verify vector column type**
   ```sql
   SELECT cardinality(text_embedding) AS dims
   FROM sandbox.default.cases_chunks
   LIMIT 1;
   ```
   Expected: `dims = 384`

**Done when:** All 7 steps pass without errors.
