import pytest
from unittest.mock import MagicMock
from pydantic import BaseModel
from spark_etl.sink import DataSink


class MyOptions(BaseModel):
    value: str


class ConcreteSink(DataSink[MyOptions]):
    def write(self, df, options):
        pass


def test_datasink_is_abstract():
    with pytest.raises(TypeError):
        DataSink()


def test_subclass_without_write_raises():
    class IncompleteSink(DataSink):
        pass
    with pytest.raises(TypeError):
        IncompleteSink()


def test_type_guard_raises_for_dict():
    sink = ConcreteSink()
    df = MagicMock()
    with pytest.raises(TypeError):
        sink.write(df, {"value": "test"})


def test_type_guard_passes_for_basemodel():
    sink = ConcreteSink()
    df = MagicMock()
    options = MyOptions(value="test")
    sink.write(df, options)
