import os
import re
import pandas as pd
from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.functions import pandas_udf, col
from pyspark.sql.types import ArrayType, FloatType, StructType, StructField, StringType, LongType, IntegerType
from spark_etl import Pipeline
from spark_etl.connectors import (
    LanceSink, LanceSinkOptions, VectorIndexSpec, FTSIndexSpec,
    GCSMarkdownSource, GCSMarkdownSourceOptions,
)

_text_model = None


def _get_text_model():
    global _text_model
    if _text_model is None:
        from sentence_transformers import SentenceTransformer
        _text_model = SentenceTransformer("all-MiniLM-L6-v2")
    return _text_model


@pandas_udf(ArrayType(FloatType()))
def encode_text(texts: pd.Series) -> pd.Series:
    model = _get_text_model()
    vecs = model.encode(texts.tolist(), normalize_embeddings=True)
    return pd.Series([v.tolist() for v in vecs])


def chunk_markdown(df: DataFrame) -> DataFrame:
    rows = df.collect()
    heading_re = re.compile(r'^(#{1,6})\s+(.+)', re.MULTILINE)
    chunks = []
    for row in rows:
        doc_id = row["doc_id"]
        file_stem = row["file_stem"]
        content = row["content"]
        matches = list(heading_re.finditer(content))
        if not matches:
            body = content.strip()
            if body:
                chunks.append({
                    "chunk_id": f"{doc_id}_0",
                    "doc_id": doc_id,
                    "file_stem": file_stem,
                    "section": "",
                    "heading_level": 0,
                    "chunk_index": 0,
                    "text": body,
                })
            continue
        for chunk_index, match in enumerate(matches):
            heading_level = len(match.group(1))
            section = match.group(2).strip()
            start = match.end()
            end = matches[chunk_index + 1].start() if chunk_index + 1 < len(matches) else len(content)
            body = content[start:end].strip()
            if not body:
                continue
            chunks.append({
                "chunk_id": f"{doc_id}_{chunk_index}",
                "doc_id": doc_id,
                "file_stem": file_stem,
                "section": section,
                "heading_level": heading_level,
                "chunk_index": chunk_index,
                "text": body,
            })

    schema = StructType([
        StructField("chunk_id", StringType(), False),
        StructField("doc_id", LongType(), False),
        StructField("file_stem", StringType(), False),
        StructField("section", StringType(), False),
        StructField("heading_level", IntegerType(), False),
        StructField("chunk_index", IntegerType(), False),
        StructField("text", StringType(), False),
    ])
    spark = df.sparkSession
    df_chunks = spark.createDataFrame(chunks, schema=schema)
    df_chunks = df_chunks.withColumn("embedding_model", F.lit("all-MiniLM-L6-v2"))
    print("Generating text embeddings (all-MiniLM-L6-v2, 384d)...")
    df_chunks = df_chunks.withColumn("text_embedding", encode_text(col("text")))
    df_chunks = df_chunks.cache()
    df_chunks.count()
    df_chunks.show(5, truncate=80)
    return df_chunks


def main():
    source = GCSMarkdownSource()
    sink_opts = LanceSinkOptions(
        catalog_name="sandbox",
        namespace="default",
        table_name="cases_chunks",
        indexes=[
            VectorIndexSpec(index_type="IVF_PQ", column="text_embedding", dimension=384, num_partitions=4, num_sub_vectors=12),
            FTSIndexSpec(column="text"),
        ],
    )
    pipeline = Pipeline(source, LanceSink())

    options = GCSMarkdownSourceOptions(
        bucket=os.environ["GCS_BUCKET"],
        prefix=os.environ["GCS_MD_PREFIX"],
    )

    df = pipeline.extract(options)
    df = pipeline.transform(df, chunk_markdown)
    pipeline.load(df, sink_opts)


if __name__ == "__main__":
    main()
