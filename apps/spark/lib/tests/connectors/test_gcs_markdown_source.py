import sys
import pytest
from unittest.mock import MagicMock, patch
from pydantic import ValidationError
from spark_etl.connectors.gcs_markdown_source import (
    GCSMarkdownSource, GCSMarkdownSourceOptions,
)


def test_options_valid():
    opts = GCSMarkdownSourceOptions(bucket="my-bucket", prefix="raw/cases_md/")
    assert opts.bucket == "my-bucket"
    assert opts.prefix == "raw/cases_md/"


def test_options_missing_bucket_raises():
    with pytest.raises(ValidationError):
        GCSMarkdownSourceOptions(prefix="raw/cases_md/")


def test_options_missing_prefix_raises():
    with pytest.raises(ValidationError):
        GCSMarkdownSourceOptions(bucket="my-bucket")


def test_read_parses_doc_id_and_file_stem():
    mock_storage = MagicMock()
    mock_blob = MagicMock()
    mock_blob.name = "raw/cases_md/thiago_x_meli/42.md"
    mock_blob.download_as_text.return_value = "## Section\nBody text"
    mock_storage.Client.return_value.list_blobs.return_value = [mock_blob]

    spark = MagicMock()
    opts = GCSMarkdownSourceOptions(bucket="justeam", prefix="raw/cases_md/")

    with patch.dict(sys.modules, {"google.cloud.storage": mock_storage}):
        GCSMarkdownSource().read(spark, opts)

    call_args = spark.createDataFrame.call_args
    rows = call_args[0][0]
    assert len(rows) == 1
    assert rows[0]["doc_id"] == 42
    assert rows[0]["file_stem"] == "thiago_x_meli"


def test_read_skips_non_md_files():
    mock_storage = MagicMock()
    md_blob = MagicMock()
    md_blob.name = "raw/cases_md/case_a/1.md"
    md_blob.download_as_text.return_value = "# Heading\ntext"
    pdf_blob = MagicMock()
    pdf_blob.name = "raw/cases_md/case_a/1.pdf"
    mock_storage.Client.return_value.list_blobs.return_value = [md_blob, pdf_blob]

    spark = MagicMock()
    opts = GCSMarkdownSourceOptions(bucket="justeam", prefix="raw/cases_md/")

    with patch.dict(sys.modules, {"google.cloud.storage": mock_storage}):
        GCSMarkdownSource().read(spark, opts)

    rows = spark.createDataFrame.call_args[0][0]
    assert len(rows) == 1
    assert rows[0]["gcs_path"].endswith("1.md")


def test_read_lists_blobs_and_creates_dataframe():
    mock_storage = MagicMock()
    mock_blob = MagicMock()
    mock_blob.name = "raw/cases_md/case_a/7.md"
    mock_blob.download_as_text.return_value = "content"
    mock_storage.Client.return_value.list_blobs.return_value = [mock_blob]

    spark = MagicMock()
    opts = GCSMarkdownSourceOptions(bucket="justeam", prefix="raw/cases_md/")

    with patch.dict(sys.modules, {"google.cloud.storage": mock_storage}):
        GCSMarkdownSource().read(spark, opts)

    mock_storage.Client.return_value.list_blobs.assert_called_once_with(
        "justeam", prefix="raw/cases_md/"
    )
    spark.createDataFrame.assert_called_once()


def test_read_skips_non_numeric_doc_id():
    mock_storage = MagicMock()
    bad_blob = MagicMock()
    bad_blob.name = "raw/cases_md/case_a/summary.md"
    mock_storage.Client.return_value.list_blobs.return_value = [bad_blob]

    spark = MagicMock()
    opts = GCSMarkdownSourceOptions(bucket="justeam", prefix="raw/cases_md/")

    with patch.dict(sys.modules, {"google.cloud.storage": mock_storage}):
        GCSMarkdownSource().read(spark, opts)

    rows = spark.createDataFrame.call_args[0][0]
    assert rows == []


def test_type_guard_rejects_dict():
    source = GCSMarkdownSource()
    spark = MagicMock()
    with pytest.raises(TypeError):
        source.read(spark, {"bucket": "b", "prefix": "p/"})
