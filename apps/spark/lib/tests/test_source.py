import pytest
from unittest.mock import MagicMock
from pydantic import BaseModel
from spark_etl.source import DataSource


class MyOptions(BaseModel):
    value: str


class ConcreteSource(DataSource[MyOptions]):
    def read(self, spark, options):
        return MagicMock()


def test_datasource_is_abstract():
    with pytest.raises(TypeError):
        DataSource()


def test_subclass_without_read_raises():
    class IncompleteSource(DataSource):
        pass
    with pytest.raises(TypeError):
        IncompleteSource()


def test_type_guard_raises_for_dict():
    src = ConcreteSource()
    spark = MagicMock()
    with pytest.raises(TypeError):
        src.read(spark, {"value": "test"})


def test_type_guard_passes_for_basemodel():
    src = ConcreteSource()
    spark = MagicMock()
    options = MyOptions(value="test")
    result = src.read(spark, options)
    assert result is not None
