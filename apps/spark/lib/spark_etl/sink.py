from abc import ABC, abstractmethod
from typing import Generic, TypeVar
from pydantic import BaseModel
from pyspark.sql import DataFrame
from spark_etl._guard import _type_guard

O = TypeVar("O", bound=BaseModel)


class DataSink(ABC, Generic[O]):
    def __init_subclass__(cls, **kwargs):
        super().__init_subclass__(**kwargs)
        if "write" in cls.__dict__ and not getattr(cls.__dict__["write"], "__isabstractmethod__", False):
            cls.write = _type_guard(cls.__dict__["write"])

    @abstractmethod
    def write(self, df: DataFrame, options: O) -> None: ...
