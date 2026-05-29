def test_core_imports():
    from spark_etl import DataSource, DataSink, Pipeline
    assert DataSource is not None
    assert DataSink is not None
    assert Pipeline is not None


def test_connector_imports():
    from spark_etl.connectors import GCSParquetSource, GCSLanceSource, LanceSink
    assert GCSParquetSource is not None
    assert GCSLanceSource is not None
    assert LanceSink is not None
