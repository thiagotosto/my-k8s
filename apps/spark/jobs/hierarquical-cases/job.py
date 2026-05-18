import os
import re
import tempfile
import pandas as pd
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.functions import pandas_udf, col
from pyspark.sql.types import ArrayType, FloatType
from pyspark.sql.window import Window
import lancedb
from lancedb.table import LanceTable
import pyarrow as pa
from google.cloud import storage

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


def _parse_gcs_uri(uri: str):
    """Return (bucket, blob_path) from a gs://bucket/path URI."""
    without_scheme = uri[len("gs://"):]
    bucket, _, blob_path = without_scheme.partition("/")
    return bucket, blob_path


def _find_lance_table_path(
    bucket: str, gcs_prefix: str, namespace: str, table_name: str, creds_path: str
) -> str:
    client = storage.Client.from_service_account_json(creds_path)
    iterator = client.list_blobs(bucket, prefix=f"{gcs_prefix}/", delimiter="/")
    prefixes = set()
    for page in iterator.pages:
        prefixes.update(page.prefixes)

    suffix = f"_{namespace}${table_name}"
    for prefix in prefixes:
        dir_name = prefix.rstrip("/").split("/")[-1]
        if dir_name.endswith(suffix):
            return f"gs://{bucket}/{prefix.rstrip('/')}"

    raise ValueError(
        f"Lance table not found: {namespace}.{table_name} in gs://{bucket}/{gcs_prefix}/"
    )


def create_indexes(bucket: str, gcs_creds: str) -> None:
    table_path = _find_lance_table_path(
        bucket, "sandbox", "default", "hierarquical_cases", gcs_creds
    )
    print(f"Found Lance table at: {table_path}")

    db = lancedb.connect(
        f"gs://{bucket}/sandbox",
        storage_options={"google_application_credentials": gcs_creds},
    )
    tbl = LanceTable.open(db, "hierarquical_cases", location=table_path)

    tbl.alter_columns(
        {"path": "text_embedding", "data_type": pa.list_(pa.float32(), 384)}
    )
    print("Cast text_embedding to FixedSizeList[384] for IVF_PQ indexing")

    try:
        tbl.create_index(
            vector_column_name="text_embedding",
            index_type="IVF_PQ",
            num_partitions=4,
            num_sub_vectors=12,
            metric="cosine",
            replace=True,
        )
        print("IVF_PQ vector index created on text_embedding (384d, cosine)")
    except Exception as exc:
        print(f"Vector index skipped ({exc}); brute-force scan will be used")

    try:
        tbl.create_fts_index("text", replace=True)
        print("FTS index created on text")
    except Exception as exc:
        print(f"FTS index skipped ({exc})")


def main():
    spark = SparkSession.builder.appName("spark-hierarquical-cases").getOrCreate()

    bucket = os.environ["GCS_BUCKET"]
    gcs_creds = os.environ["GOOGLE_APPLICATION_CREDENTIALS"]
    pdf_uri = os.environ["GCS_PDF_PATH"]

    # --- Phase 1: Download PDF to driver local temp file ---
    pdf_bucket, pdf_blob = _parse_gcs_uri(pdf_uri)
    gcs_client = storage.Client.from_service_account_json(gcs_creds)
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        gcs_client.bucket(pdf_bucket).blob(pdf_blob).download_to_filename(tmp.name)
        pdf_path = tmp.name
    print(f"PDF downloaded to {pdf_path}")

    # --- Phase 2: Extract page index with PyPDF ---
    from pypdf import PdfReader
    reader = PdfReader(pdf_path)
    documents_raw = []
    for p, page in enumerate(reader.pages):
        text = page.extract_text() or ""
        match = re.search(r"Num. ([1-9][0-9]*) - Pág. ([1-9][0-9]*)", text)
        if match:
            documents_raw.append({
                "page": p + 1,
                "idx": match.group(1),
                "piece_page": match.group(2),
            })

    # --- Phase 3: Compute doc page ranges in Spark, take first 2 docs ---
    df_index = spark.createDataFrame(documents_raw)
    df_min_max = (
        df_index.groupBy("idx")
        .agg(
            F.min("page").alias("min_page"),
            F.max("page").alias("max_page"),
        )
        .orderBy("min_page")
        .limit(2)
    )
    doc_ranges = df_min_max.collect()
    print(f"Processing {len(doc_ranges)} documents: {[r['idx'] for r in doc_ranges]}")

    # --- Phase 4: Docling conversion on driver (sequential, OCR-heavy) ---
    from docling.document_converter import DocumentConverter, PdfFormatOption
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PdfPipelineOptions

    pipeline_options = PdfPipelineOptions(do_ocr=False)

    all_texts = []
    for row in doc_ranges:
        converter = DocumentConverter(
            allowed_formats=[InputFormat.PDF],
            format_options={
                InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options)
            },
        )
        doc_dict = converter.convert(
            source=pdf_path,
            page_range=(int(row["min_page"]), int(row["max_page"])),
        ).document.export_to_dict()

        for i, text_item in enumerate(doc_dict.get("texts", [])):
            all_texts.append({
                "doc_id": int(row["idx"]),
                "row_idx": i,
                "self_ref": text_item.get("self_ref", ""),
                "label": text_item.get("label", ""),
                "text": text_item.get("text", ""),
            })

    os.unlink(pdf_path)

    # --- Phase 5: Build df_texts as Spark DataFrame ---
    df_texts = spark.createDataFrame(all_texts)

    # --- Phase 6: Section headers + lead() for previous_section_index ---
    w = Window.partitionBy("doc_id").orderBy("row_idx")
    df_headers = df_texts.filter(col("label") == "section_header").select(
        "doc_id",
        col("row_idx").alias("index_y"),
        col("text").alias("text_y"),
        F.lead("row_idx").over(w).alias("previous_section_index"),
    )

    # --- Phase 7: Join all texts with section headers, filter by position ---
    df_all = df_texts.select(
        "doc_id",
        col("row_idx").alias("index_x"),
        col("text").alias("text_x"),
    )

    result = (
        df_all.join(df_headers, on="doc_id", how="inner")
        .filter(
            (col("index_x") > col("index_y"))
            & (col("index_x") < col("previous_section_index"))
        )
        .select(
            "doc_id",
            "index_x",
            col("text_x").alias("text"),
            col("text_y").alias("section"),
            "index_y",
            "previous_section_index",
        )
    )

    # --- Phase 8: Text embeddings via pandas_udf ---
    print("Generating text embeddings (all-MiniLM-L6-v2, 384d)...")
    result = result.withColumn("text_embedding", encode_text(col("text")))
    result = result.cache()
    result.count()
    result.show(5, truncate=80)

    # --- Phase 9: Write to Lance sandbox catalog ---
    spark.sql("CREATE NAMESPACE IF NOT EXISTS sandbox.default")
    result.writeTo("sandbox.default.hierarquical_cases") \
          .overwrite() \
          .using("lance") \
          .createOrReplace()
    print("Lance table written → sandbox.default.hierarquical_cases")

    # --- Phase 10: Vector index + FTS index ---
    create_indexes(bucket, gcs_creds)

    spark.stop()


if __name__ == "__main__":
    main()
