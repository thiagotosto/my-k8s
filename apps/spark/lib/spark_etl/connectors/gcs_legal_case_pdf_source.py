import re
import tempfile
from pydantic import BaseModel
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.functions import col, lit
from spark_etl.source import DataSource


class GCSLegalCasePDFOptions(BaseModel):
    bucket: str
    blob_name: str


class GCSLegalCasePDFSource(DataSource[GCSLegalCasePDFOptions]):
    def read(self, spark: SparkSession, options: GCSLegalCasePDFOptions) -> DataFrame:
        from google.cloud import storage
        gcs_client = storage.Client()
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
            gcs_client.bucket(options.bucket).blob(options.blob_name).download_to_filename(tmp.name)
            pdf_path = tmp.name
        print(f"PDF downloaded to {pdf_path}")

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

        df_index = spark.createDataFrame(documents_raw)
        doc_ranges = (
            df_index.groupBy("idx")
            .agg(
                F.min("page").alias("min_page"),
                F.max("page").alias("max_page"),
            )
            .orderBy("min_page")
            .limit(4)
            .withColumn("doc_id", col("idx").cast("int"))
            .drop("idx")
            .withColumn("pdf_path", lit(pdf_path))
        )
        return doc_ranges
