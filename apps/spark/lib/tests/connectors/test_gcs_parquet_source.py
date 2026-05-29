import pytest
from unittest.mock import MagicMock
from pydantic import ValidationError
from spark_etl.connectors.gcs_parquet_source import GCSParquetSource, GCSParquetOptions


def test_options_valid_minimal():
    opts = GCSParquetOptions(bucket="my-bucket", path="data/")
    assert opts.bucket == "my-bucket"
    assert opts.path == "data/"


def test_options_missing_bucket_raises():
    with pytest.raises(ValidationError):
        GCSParquetOptions(path="data/")


def test_options_missing_path_raises():
    with pytest.raises(ValidationError):
        GCSParquetOptions(bucket="my-bucket")


def test_read_builds_correct_gcs_uri():
    src = GCSParquetSource()
    spark = MagicMock()
    opts = GCSParquetOptions(bucket="my-bucket", path="data/")
    src.read(spark, opts)
    spark.read.parquet.assert_called_once_with("gs://my-bucket/data/")


def test_type_guard_inherited():
    src = GCSParquetSource()
    spark = MagicMock()
    with pytest.raises(TypeError):
        src.read(spark, {"bucket": "my-bucket", "path": "data/"})
