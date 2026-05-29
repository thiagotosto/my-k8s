from typing import Optional
from pydantic import BaseModel
from pyspark.sql import SparkSession, DataFrame
from spark_etl.source import DataSource


class GCSParquetOptions(BaseModel):
    bucket: str
    path: str
    credentials_path: Optional[str] = None


class GCSParquetSource(DataSource[GCSParquetOptions]):
    def read(self, spark: SparkSession, options: GCSParquetOptions) -> DataFrame:
        return spark.read.parquet(f"gs://{options.bucket}/{options.path}")
