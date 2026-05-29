from pydantic import BaseModel
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.types import StructType, StructField, LongType, StringType
from spark_etl.source import DataSource


class GCSMarkdownSourceOptions(BaseModel):
    bucket: str
    prefix: str


class GCSMarkdownSource(DataSource[GCSMarkdownSourceOptions]):
    def read(self, spark: SparkSession, options: GCSMarkdownSourceOptions) -> DataFrame:
        from google.cloud import storage
        client = storage.Client()
        blobs = client.list_blobs(options.bucket, prefix=options.prefix)
        rows = []
        for blob in blobs:
            if not blob.name.endswith(".md"):
                continue
            relative = blob.name[len(options.prefix):]
            parts = relative.split("/")
            if len(parts) != 2:
                continue
            file_stem, filename = parts
            try:
                doc_id = int(filename[:-3])
            except ValueError:
                continue
            content = blob.download_as_text()
            rows.append({
                "doc_id": doc_id,
                "file_stem": file_stem,
                "content": content,
                "gcs_path": f"gs://{options.bucket}/{blob.name}",
            })
        schema = StructType([
            StructField("doc_id", LongType(), False),
            StructField("file_stem", StringType(), False),
            StructField("content", StringType(), False),
            StructField("gcs_path", StringType(), False),
        ])
        return spark.createDataFrame(rows, schema=schema)
