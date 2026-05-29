from pydantic import BaseModel
from pyspark.sql import SparkSession, DataFrame
from spark_etl.source import DataSource


class GCSLanceOptions(BaseModel):
    catalog_name: str
    namespace: str
    table_name: str


class GCSLanceSource(DataSource[GCSLanceOptions]):
    def read(self, spark: SparkSession, options: GCSLanceOptions) -> DataFrame:
        return spark.table(f"{options.catalog_name}.{options.namespace}.{options.table_name}")
