import pytest
from unittest.mock import MagicMock
from pydantic import ValidationError
from spark_etl.connectors.gcs_lance_source import GCSLanceSource, GCSLanceOptions


def test_options_valid():
    opts = GCSLanceOptions(catalog_name="bronze", namespace="default", table_name="products")
    assert opts.catalog_name == "bronze"


def test_options_missing_catalog_name_raises():
    with pytest.raises(ValidationError):
        GCSLanceOptions(namespace="default", table_name="products")


def test_options_missing_namespace_raises():
    with pytest.raises(ValidationError):
        GCSLanceOptions(catalog_name="bronze", table_name="products")


def test_options_missing_table_name_raises():
    with pytest.raises(ValidationError):
        GCSLanceOptions(catalog_name="bronze", namespace="default")


def test_read_calls_spark_table_with_full_name():
    src = GCSLanceSource()
    spark = MagicMock()
    opts = GCSLanceOptions(catalog_name="bronze", namespace="default", table_name="products")
    src.read(spark, opts)
    spark.table.assert_called_once_with("bronze.default.products")
