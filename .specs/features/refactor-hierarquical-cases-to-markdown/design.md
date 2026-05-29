# Design: refactor-hierarquical-cases-to-markdown

## Data Flow

```
GCS gs://justeam/raw/cases_md/**/*.md
        │
        ▼
GCSMarkdownSource.read()          [driver]
  list_blobs → download_as_text()
  returns DataFrame(doc_id, file_stem, content, gcs_path)
        │
        ▼
chunk_markdown(df)                [driver — df.collect()]
  regex heading parse per doc
  emit one row per section chunk
  returns DataFrame(chunk_id, doc_id, file_stem, section,
                    heading_level, chunk_index, text,
                    embedding_model)
        │
        ▼
encode_text pandas_udf            [executors — distributed]
  sentence-transformers all-MiniLM-L6-v2 → 384d float array
  returns text_embedding column
        │
        ▼
LanceSink.write()
  sandbox.default.cases_chunks
  IVF_PQ on text_embedding (dim=384, partitions=4, sub_vecs=12)
  FTS on text
```

## Component Design

### GCSMarkdownSource

Follows the same driver-side download pattern as `GCSLegalCasePDFSource`. Markdown files are small (tens of KB each), so collecting them all in the driver before creating a DataFrame is appropriate at the expected corpus size (hundreds of legal cases).

```python
class GCSMarkdownSourceOptions(BaseModel):
    bucket: str
    prefix: str  # "raw/cases_md/"

class GCSMarkdownSource(DataSource[GCSMarkdownSourceOptions]):
    def read(self, spark, options) -> DataFrame:
        client = storage.Client()
        blobs = client.list_blobs(options.bucket, prefix=options.prefix)
        rows = []
        for blob in blobs:
            # filter: must end in .md and have numeric doc_id
            # path structure: {prefix}{file_stem}/{doc_id}.md
            ...
        schema = StructType([
            StructField("doc_id",    LongType(),   False),
            StructField("file_stem", StringType(), False),
            StructField("content",   StringType(), False),
            StructField("gcs_path",  StringType(), False),
        ])
        return spark.createDataFrame(rows, schema=schema)
```

Explicit schema avoids Spark schema inference over an empty list (edge case: no `.md` files found returns an empty DataFrame with the correct structure).

### chunk_markdown transform

Heading-based splitting using `re.MULTILINE` on `^(#{1,6})\s+(.+)`. This matches Docling's markdown output which uses ATX headings (`#`, `##`, etc.) for section hierarchy in legal documents.

```
Input row:  doc_id=42, content="## Intro\nFatos...\n## Decisão\nPor isso..."

Matches:    [(pos=0, level=2, heading="Intro"),
             (pos=20, level=2, heading="Decisão")]

Chunks:     {doc_id=42, chunk_index=0, section="Intro",   text="Fatos..."}
            {doc_id=42, chunk_index=1, section="Decisão", text="Por isso..."}
```

Fallback: if `re.finditer` finds zero headings, the entire content becomes one chunk with `section=""`, `heading_level=0`. This handles edge cases (e.g., a doc that is pure prose with no ATX headings).

`embedding_model` is written as a literal string column (`F.lit("all-MiniLM-L6-v2")`) so the table is self-describing as the model evolves.

### Embedding step (unchanged)

`encode_text` pandas UDF is identical to the current job — lazy-loaded global model, `normalize_embeddings=True`. No changes needed.

### LanceSink / indexes (unchanged)

Same `VectorIndexSpec` + `FTSIndexSpec` configuration. Only the `table_name` changes: `hierarquical_cases` → `cases_chunks`.

## Resource Impact

Removing Docling from the transform eliminates the heaviest CPU/memory step in the current job. The dominant cost shifts to sentence-transformer inference (already present). Executor memory could be reduced from `3g` to `2g`, but this is left for a follow-up after GKE validation — changing it now adds scope without new data.

## Files

| File | Type | Change |
|------|------|--------|
| `spark_etl/connectors/gcs_markdown_source.py` | new | GCSMarkdownSource + options |
| `spark_etl/connectors/__init__.py` | mod | add export |
| `tests/connectors/test_gcs_markdown_source.py` | new | 7 unit tests |
| `jobs/hierarquical-cases/job.py` | mod | swap source + transform, rename table |
| `jobs/hierarquical-cases/spark.yaml` | mod | swap env vars |
| `Dockerfile` | mod | remove docling layer |
