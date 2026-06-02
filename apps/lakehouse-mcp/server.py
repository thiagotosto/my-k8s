import logging
import os
from typing import Any

import lancedb
import trino.dbapi
from mcp.server.fastmcp import FastMCP
from sentence_transformers import SentenceTransformer

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

model = SentenceTransformer("all-MiniLM-L6-v2")
db = lancedb.connect(os.environ["LANCE_URI"])
_tables: dict[str, Any] = {}

TABLES = {
    "cases_summaries": {"vector_col": "resumo_embedding", "fts": True},
    "cases_chunks": {"vector_col": "text_embedding", "fts": True},
}

TRINO_HOST = os.environ.get("TRINO_HOST", "trino.trino.svc.cluster.local")
TRINO_PORT = int(os.environ.get("TRINO_PORT", "8080"))


def _get_table(name: str) -> Any:
    if name not in TABLES:
        raise ValueError(f"Unknown table: {name}")
    if name not in _tables:
        _tables[name] = db.open_table(name)
    return _tables[name]


mcp = FastMCP("lakehouse-mcp")


@mcp.tool()
def query_vector(
    table: str, query_text: str, k: int = 10, filter: str | None = None
) -> list[dict]:
    """Find semantically similar rows via vector similarity search."""
    try:
        meta = TABLES.get(table)
        if meta is None:
            return [{"error": f"Unknown table: {table}"}]
        tbl = _get_table(table)
        vec = model.encode(query_text, normalize_embeddings=True).tolist()
        q = (
            tbl.search(vec, vector_column_name=meta["vector_col"])
            .metric("cosine")
            .limit(k)
        )
        if filter:
            q = q.where(filter)
        return q.to_list()
    except Exception as e:
        return [{"error": str(e)}]


@mcp.tool()
def query_fts(
    table: str, query: str, k: int = 10, filter: str | None = None
) -> list[dict]:
    """Find rows by keyword via full-text search."""
    try:
        meta = TABLES.get(table)
        if meta is None:
            return [{"error": f"Unknown table: {table}"}]
        if not meta["fts"]:
            return [{"error": f"FTS index not available for table {table}"}]
        tbl = _get_table(table)
        q = tbl.search(query, query_type="fts").limit(k)
        if filter:
            q = q.where(filter)
        return q.to_list()
    except Exception as e:
        return [{"error": str(e)}]


@mcp.tool()
def query_sql(sql: str) -> list[dict]:
    """Run arbitrary SQL against the Trino cluster."""
    try:
        conn = trino.dbapi.connect(
            host=TRINO_HOST,
            port=TRINO_PORT,
            user="mcp",
            catalog="sandbox",
        )
        cursor = conn.cursor()
        cursor.execute(sql)
        cols = [d[0] for d in cursor.description]
        return [dict(zip(cols, row)) for row in cursor.fetchall()]
    except Exception as e:
        return [{"error": str(e)}]


if __name__ == "__main__":
    mcp.run(transport="sse")
