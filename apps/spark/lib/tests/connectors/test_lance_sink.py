import sys
import pytest
from unittest.mock import MagicMock, patch
from pydantic import ValidationError
from spark_etl.connectors.lance_sink import (
    LanceSink, LanceSinkOptions, VectorIndexSpec, ScalarIndexSpec, FTSIndexSpec,
)


def test_options_valid_minimal():
    opts = LanceSinkOptions(catalog_name="bronze", namespace="default", table_name="products")
    assert opts.mode == "overwrite"


def test_options_mode_append_valid():
    opts = LanceSinkOptions(catalog_name="bronze", namespace="default", table_name="products", mode="append")
    assert opts.mode == "append"


def test_options_invalid_mode_raises():
    with pytest.raises(ValidationError):
        LanceSinkOptions(catalog_name="bronze", namespace="default", table_name="products", mode="delete")


def test_options_missing_catalog_name_raises():
    with pytest.raises(ValidationError):
        LanceSinkOptions(namespace="default", table_name="products")


def _make_df_mock():
    df = MagicMock()
    df.sparkSession = MagicMock()
    mock_writer = MagicMock()
    df.writeTo.return_value.using.return_value = mock_writer
    return df, mock_writer


def test_write_creates_namespace():
    sink = LanceSink()
    df, _ = _make_df_mock()
    opts = LanceSinkOptions(catalog_name="bronze", namespace="default", table_name="products")
    sink.write(df, opts)
    df.sparkSession.sql.assert_called_once_with("CREATE NAMESPACE IF NOT EXISTS bronze.default")


def test_write_full_table_name():
    sink = LanceSink()
    df, _ = _make_df_mock()
    opts = LanceSinkOptions(catalog_name="bronze", namespace="default", table_name="products")
    sink.write(df, opts)
    df.writeTo.assert_called_once_with("bronze.default.products")


def test_write_mode_overwrite_calls_create_or_replace():
    sink = LanceSink()
    df, mock_writer = _make_df_mock()
    opts = LanceSinkOptions(catalog_name="bronze", namespace="default", table_name="products", mode="overwrite")
    sink.write(df, opts)
    mock_writer.createOrReplace.assert_called_once()


def test_write_mode_append_calls_append():
    sink = LanceSink()
    df, mock_writer = _make_df_mock()
    opts = LanceSinkOptions(catalog_name="bronze", namespace="default", table_name="products", mode="append")
    sink.write(df, opts)
    mock_writer.append.assert_called_once()


# --- Index creation tests ---

def _make_index_df_mock(catalog_root="gs://test-bucket/test-prefix"):
    df = MagicMock()
    spark = MagicMock()
    spark.conf.get.return_value = catalog_root
    df.sparkSession = spark
    mock_writer = MagicMock()
    df.writeTo.return_value.using.return_value = mock_writer
    return df, mock_writer


def _lancedb_ctx(mock_tbl):
    mock_lancedb = MagicMock()
    mock_lancedb.connect.return_value = MagicMock()
    mock_lancedb_table = MagicMock()
    mock_lancedb_table.LanceTable.open.return_value = mock_tbl
    return patch.dict(sys.modules, {
        "lancedb": mock_lancedb,
        "lancedb.table": mock_lancedb_table,
        "pyarrow": MagicMock(),
    })


def test_options_accepts_all_index_spec_types():
    opts = LanceSinkOptions(
        catalog_name="x", namespace="y", table_name="z",
        indexes=[
            VectorIndexSpec(index_type="IVF_PQ", column="vec", dimension=128),
            ScalarIndexSpec(index_type="BTREE", column="id"),
            FTSIndexSpec(column="text"),
        ],
    )
    assert len(opts.indexes) == 3


def test_write_empty_indexes_no_lancedb_calls():
    sink = LanceSink()
    df, _ = _make_df_mock()
    opts = LanceSinkOptions(catalog_name="a", namespace="b", table_name="c")
    # lancedb absent from sys.modules — any import attempt would raise ImportError
    sink.write(df, opts)


def test_vector_index_with_dimension_calls_alter_then_create():
    mock_tbl = MagicMock()
    df, _ = _make_index_df_mock()
    opts = LanceSinkOptions(
        catalog_name="sandbox", namespace="default", table_name="t",
        indexes=[VectorIndexSpec(index_type="IVF_PQ", column="vec", dimension=64, num_sub_vectors=4)],
    )
    with _lancedb_ctx(mock_tbl):
        with patch("spark_etl.connectors.lance_sink._find_lance_table_path", return_value="gs://b/p/t"):
            LanceSink().write(df, opts)

    mock_tbl.alter_columns.assert_called_once()
    mock_tbl.create_index.assert_called_once()
    assert mock_tbl.create_index.call_args.kwargs["index_type"] == "IVF_PQ"
    assert mock_tbl.create_index.call_args.kwargs["num_sub_vectors"] == 4


def test_vector_index_without_dimension_no_alter_columns():
    mock_tbl = MagicMock()
    df, _ = _make_index_df_mock()
    opts = LanceSinkOptions(
        catalog_name="sandbox", namespace="default", table_name="t",
        indexes=[VectorIndexSpec(index_type="IVF_FLAT", column="vec")],
    )
    with _lancedb_ctx(mock_tbl):
        with patch("spark_etl.connectors.lance_sink._find_lance_table_path", return_value="gs://b/p/t"):
            LanceSink().write(df, opts)

    mock_tbl.alter_columns.assert_not_called()
    mock_tbl.create_index.assert_called_once()


def test_fts_index_calls_create_fts_index():
    mock_tbl = MagicMock()
    df, _ = _make_index_df_mock()
    opts = LanceSinkOptions(
        catalog_name="sandbox", namespace="default", table_name="t",
        indexes=[FTSIndexSpec(column="text", language="Portuguese")],
    )
    with _lancedb_ctx(mock_tbl):
        with patch("spark_etl.connectors.lance_sink._find_lance_table_path", return_value="gs://b/p/t"):
            LanceSink().write(df, opts)

    mock_tbl.create_fts_index.assert_called_once_with(
        "text", replace=True, language="Portuguese",
        lower_case=True, stem=True, remove_stop_words=True, ascii_folding=True,
    )


def test_scalar_index_calls_create_scalar_index():
    mock_tbl = MagicMock()
    df, _ = _make_index_df_mock()
    opts = LanceSinkOptions(
        catalog_name="sandbox", namespace="default", table_name="t",
        indexes=[ScalarIndexSpec(index_type="BTREE", column="category")],
    )
    with _lancedb_ctx(mock_tbl):
        with patch("spark_etl.connectors.lance_sink._find_lance_table_path", return_value="gs://b/p/t"):
            LanceSink().write(df, opts)

    mock_tbl.create_scalar_index.assert_called_once_with(
        "category", index_type="BTREE", replace=True,
    )


def test_index_exception_is_swallowed():
    mock_tbl = MagicMock()
    mock_tbl.create_index.side_effect = RuntimeError("lancedb error")
    df, _ = _make_index_df_mock()
    opts = LanceSinkOptions(
        catalog_name="sandbox", namespace="default", table_name="t",
        indexes=[VectorIndexSpec(index_type="IVF_FLAT", column="vec")],
    )
    with _lancedb_ctx(mock_tbl):
        with patch("spark_etl.connectors.lance_sink._find_lance_table_path", return_value="gs://b/p/t"):
            LanceSink().write(df, opts)  # must not raise
