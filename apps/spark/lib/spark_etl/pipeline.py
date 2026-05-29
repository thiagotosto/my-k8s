from typing import Callable
from pydantic import BaseModel
from pyspark.sql import SparkSession, DataFrame
from spark_etl.source import DataSource
from spark_etl.sink import DataSink


class Pipeline:
    def __init__(self, source: DataSource, sink: DataSink) -> None:
        self._source = source
        self._sink = sink
        self._spark = SparkSession.builder.getOrCreate()

    def extract(self, options: BaseModel) -> DataFrame:
        return self._source.read(self._spark, options)

    def transform(self, df: DataFrame, fn: Callable[[DataFrame], DataFrame]) -> DataFrame:
        return fn(df)

    def load(self, df: DataFrame, options: BaseModel) -> None:
        self._sink.write(df, options)
