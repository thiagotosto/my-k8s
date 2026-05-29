from abc import ABC, abstractmethod
from typing import Generic, TypeVar
from pydantic import BaseModel
from pyspark.sql import SparkSession, DataFrame
from spark_etl._guard import _type_guard

O = TypeVar("O", bound=BaseModel)


class DataSource(ABC, Generic[O]):
    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)
        if "read" in cls.__dict__ and not getattr(cls.__dict__["read"], "__isabstractmethod__", False):
            cls.read = _type_guard(cls.__dict__["read"])

    @abstractmethod
    def read(self, spark: SparkSession, options: O) -> DataFrame: ...
