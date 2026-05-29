import sys
import pytest
from unittest.mock import MagicMock, patch
from pydantic import ValidationError
from spark_etl.connectors.gcs_legal_case_pdf_source import (
    GCSLegalCasePDFSource, GCSLegalCasePDFOptions,
)


def test_options_valid():
    opts = GCSLegalCasePDFOptions(bucket="my-bucket", blob_name="cases/file.pdf")
    assert opts.bucket == "my-bucket"
    assert opts.blob_name == "cases/file.pdf"


def test_options_missing_bucket_raises():
    with pytest.raises(ValidationError):
        GCSLegalCasePDFOptions(blob_name="cases/file.pdf")


def test_options_missing_blob_name_raises():
    with pytest.raises(ValidationError):
        GCSLegalCasePDFOptions(bucket="my-bucket")


def test_read_downloads_pdf_and_calls_create_dataframe():
    mock_storage = MagicMock()
    mock_pypdf = MagicMock()

    mock_page = MagicMock()
    mock_page.extract_text.return_value = "Num. 1 - Pág. 1 some legal text"
    mock_pypdf.PdfReader.return_value.pages = [mock_page]

    mock_tmp = MagicMock()
    mock_tmp.__enter__ = MagicMock(return_value=mock_tmp)
    mock_tmp.__exit__ = MagicMock(return_value=False)
    mock_tmp.name = "/tmp/test_case.pdf"

    spark = MagicMock()
    opts = GCSLegalCasePDFOptions(bucket="my-bucket", blob_name="cases/file.pdf")

    # F.min/F.max/col/lit all require an active SparkContext; patch them at module level
    with patch.dict(sys.modules, {"google.cloud.storage": mock_storage, "pypdf": mock_pypdf}), \
         patch("tempfile.NamedTemporaryFile", return_value=mock_tmp), \
         patch("spark_etl.connectors.gcs_legal_case_pdf_source.F"), \
         patch("spark_etl.connectors.gcs_legal_case_pdf_source.col"), \
         patch("spark_etl.connectors.gcs_legal_case_pdf_source.lit"):
        GCSLegalCasePDFSource().read(spark, opts)

    mock_storage.Client.return_value.bucket.assert_called_with("my-bucket")
    mock_storage.Client.return_value.bucket.return_value.blob.assert_called_with("cases/file.pdf")
    spark.createDataFrame.assert_called_once()


def test_type_guard_rejects_dict():
    source = GCSLegalCasePDFSource()
    spark = MagicMock()
    with pytest.raises(TypeError):
        source.read(spark, {"bucket": "b", "blob_name": "f.pdf"})
