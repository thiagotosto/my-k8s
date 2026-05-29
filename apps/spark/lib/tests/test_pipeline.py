import pytest
from unittest.mock import MagicMock, patch
from spark_etl.pipeline import Pipeline


@pytest.fixture
def mock_spark():
    with patch("spark_etl.pipeline.SparkSession") as mock_spark_cls:
        mock_instance = MagicMock()
        mock_spark_cls.builder.getOrCreate.return_value = mock_instance
        yield mock_spark_cls, mock_instance


def test_pipeline_stores_source_and_sink(mock_spark):
    source = MagicMock()
    sink = MagicMock()
    pipeline = Pipeline(source, sink)
    assert pipeline._source is source
    assert pipeline._sink is sink


def test_pipeline_calls_get_or_create(mock_spark):
    mock_spark_cls, _ = mock_spark
    Pipeline(MagicMock(), MagicMock())
    mock_spark_cls.builder.getOrCreate.assert_called_once()


def test_extract_delegates_to_source_read(mock_spark):
    mock_spark_cls, mock_instance = mock_spark
    source = MagicMock()
    sink = MagicMock()
    pipeline = Pipeline(source, sink)
    options = MagicMock()
    result = pipeline.extract(options)
    source.read.assert_called_once_with(mock_instance, options)
    assert result is source.read.return_value


def test_transform_applies_fn(mock_spark):
    pipeline = Pipeline(MagicMock(), MagicMock())
    df = MagicMock()
    fn = MagicMock()
    result = pipeline.transform(df, fn)
    assert result is fn.return_value


def test_transform_does_not_pass_extra_args(mock_spark):
    pipeline = Pipeline(MagicMock(), MagicMock())
    df = MagicMock()
    fn = MagicMock()
    pipeline.transform(df, fn)
    fn.assert_called_once_with(df)


def test_load_delegates_to_sink_write(mock_spark):
    pipeline = Pipeline(MagicMock(), MagicMock())
    df = MagicMock()
    options = MagicMock()
    result = pipeline.load(df, options)
    pipeline._sink.write.assert_called_once_with(df, options)
    assert result is None
