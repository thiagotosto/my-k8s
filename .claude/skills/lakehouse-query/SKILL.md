---
name: lakehouse-query
description: >
  Expert guide for querying the lakehouse context store via MCP tools.
  Triggers when: querying cases, vector search, similarity search,
  FTS search, full-text search on cases, query_vector, query_fts,
  query_sql, find similar cases, search case summaries, search case chunks,
  Trino SQL on Lance tables.
license: MIT
metadata:
  author: Thiago Tosto
  version: 1.0.0
---

# Lakehouse Query Guide

You have access to three MCP tools backed by LanceDB and Trino. Use this guide to pick the
right tool, write correct calls, and interpret results.

---

## MCP Server Connection

The MCP server runs in-cluster at:

```
http://lakehouse-mcp.lakehouse-mcp.svc.cluster.local:8000/sse
```

This is pre-configured in `/paperclip/.claude/settings.json` (provisioned by Terraform). To
confirm the agent can reach the server, verify `settings.json` contains:

```json
{
  "mcpServers": {
    "lakehouse": {
      "url": "http://lakehouse-mcp.lakehouse-mcp.svc.cluster.local:8000/sse"
    }
  }
}
```

---

## Tool Reference

### `query_vector`

Find semantically similar rows using vector similarity search.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `table` | string | required | `"cases_summaries"` or `"cases_chunks"` |
| `query_text` | string | required | Natural language query to embed and search |
| `k` | integer | 10 | Number of results to return |
| `filter` | string | null | SQL WHERE fragment (e.g. `"tipo_documento = 'SENTENCA'"`) |

**Returns:** JSON array of row objects. On error: `[{"error": "..."}]`.

**Backend:** embeds `query_text` with all-MiniLM-L6-v2 → LanceDB cosine similarity search.

---

### `query_fts`

Find rows by keyword or phrase using full-text search.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `table` | string | required | `"cases_summaries"` or `"cases_chunks"` |
| `query` | string | required | Keyword or phrase to search |
| `k` | integer | 10 | Number of results to return |
| `filter` | string | null | SQL WHERE fragment |

**Returns:** JSON array of row objects. Returns `[{"error": "FTS index not available for table X"}]`
for tables without an FTS index.

**Backend:** LanceDB `.search(query, query_type="fts")`.

---

### `query_sql`

Run arbitrary SQL against Trino.

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sql` | string | required | Valid Trino SQL; tables are at `sandbox.default.<table_name>` |

**Returns:** JSON array of row objects. On error: `[{"error": "..."}]`.

**Backend:** `trino.dbapi` connecting to `trino.trino.svc.cluster.local:8080`.

---

## Table Reference

### `cases_summaries`

GCS path: `gs://justeam/sandbox/default$cases_summaries/`
Trino ref: `sandbox.default.cases_summaries`

| Column | Type | Notes |
|--------|------|-------|
| `doc_id` | string | Case identifier (idempotency key) |
| `file_stem` | string | Source PDF filename without extension |
| `tipo_documento` | string | `PETICAO_INICIAL`, `SENTENCA`, `CONTESTACAO`, `DESPACHO` |
| `polo_emissor` | string | `AUTOR`, `REU`, `JUIZ`, `TERCEIRO` |
| `data_juntada` | string | Filing date (ISO-8601 or as extracted) |
| `pagina_inicio` | integer | First page of this case in the PDF |
| `pagina_fim` | integer | Last page |
| `resumo` | string | Structured Markdown summary |
| `resumo_embedding` | float32[384] | all-MiniLM-L6-v2 embedding of `resumo` |
| `processed_at` | string | ISO-8601 processing timestamp |

**Indexes:**
- Vector: `IVF_PQ` on `resumo_embedding` (dim=384, cosine, partitions=4)
- FTS: on `resumo` (language=Portuguese, lower_case=True, stem=True)

---

### `cases_chunks`

GCS path: `gs://justeam/sandbox/default$cases_chunks/`
Trino ref: `sandbox.default.cases_chunks`

| Column | Type | Notes |
|--------|------|-------|
| `chunk_id` | string | Unique chunk identifier |
| `doc_id` | long | Foreign key to `cases_summaries.doc_id` |
| `file_stem` | string | Source PDF filename without extension |
| `section` | string | Markdown heading the chunk belongs to |
| `heading_level` | integer | Heading depth (1–6) |
| `chunk_index` | integer | Position within the section |
| `text` | string | Raw chunk text |
| `embedding_model` | string | Model name used to generate the embedding |
| `text_embedding` | float32[384] | all-MiniLM-L6-v2 embedding of `text` |

**Indexes:**
- Vector: `IVF_PQ` on `text_embedding` (dim=384, cosine, partitions=4)
- FTS: on `text` (language=English)

---

## Decision Guide

| Use case | Tool |
|----------|------|
| "find cases similar to X" | `query_vector` on `cases_summaries` |
| "find case chunks similar to X" | `query_vector` on `cases_chunks` |
| "find cases mentioning [exact term]" | `query_fts` on `cases_summaries` |
| "find chunks mentioning [exact term]" | `query_fts` on `cases_chunks` |
| "count/group/filter by structured field" | `query_sql` |
| "look up specific doc_id" | `query_sql` with WHERE |
| "summarize a case by keyword + context" | `query_fts` then `query_vector` |

**Rule:** Use `query_fts` when exact terminology matters (party names, legal terms). Use
`query_vector` when conceptual/semantic similarity matters. Use `query_sql` for aggregations,
counts, or structured filters.

---

## Worked Examples

### Vector search — find summaries similar to a legal situation

```python
query_vector(
    table="cases_summaries",
    query_text="rescisão contratual por justa causa",
    k=5,
    filter="tipo_documento = 'SENTENCA'"
)
```

Returns up to 5 rows from `cases_summaries` with `tipo_documento = 'SENTENCA'` ordered by
cosine similarity to the query. Each row includes `doc_id`, `resumo`, `tipo_documento`, etc.

---

### FTS search — find summaries by keyword

```python
query_fts(
    table="cases_summaries",
    query="verbas rescisórias",
    k=10
)
```

Returns up to 10 rows whose `resumo` contains or stems to "verbas rescisórias".

---

### SQL — count cases by document type

```python
query_sql("SELECT tipo_documento, count(*) AS total FROM sandbox.default.cases_summaries GROUP BY tipo_documento ORDER BY total DESC")
```

Returns one row per `tipo_documento` with its count.

---

### SQL — look up a specific case

```python
query_sql("SELECT * FROM sandbox.default.cases_summaries WHERE doc_id = 'abc123' LIMIT 1")
```

---

## Filter Syntax

Filters are SQL WHERE fragments passed as strings. Examples:

```
"tipo_documento = 'SENTENCA'"
"polo_emissor = 'JUIZ'"
"pagina_inicio > 10"
"tipo_documento = 'PETICAO_INICIAL' AND polo_emissor = 'AUTOR'"
```

Filters apply to both `query_vector` and `query_fts`. Column names must match exactly.

---

## Gotchas

- Some rows in `cases_summaries` have empty `resumo_embedding` (rare write failures during
  indexing). `query_vector` will skip these; `query_sql` will return them.
- `cases_chunks.text` content is in Portuguese even though the FTS index was built with
  `language=English`. FTS keyword matching still works but stemming may be imprecise.
- `query_sql` opens a new Trino connection per call — acceptable for low-frequency tool use.
- `query_fts` on `cases_chunks` searches the `text` column (not `section`).
