from typing import Annotated, Literal, Optional, Union
from pydantic import BaseModel, Field
from pyspark.sql import SparkSession, DataFrame
from spark_etl.sink import DataSink


class VectorIndexSpec(BaseModel):
    index_type: Literal["IVF_FLAT", "IVF_PQ", "IVF_RQ", "IVF_SQ", "IVF_HNSW_FLAT", "IVF_HNSW_PQ", "IVF_HNSW_SQ"]
    column: str
    dimension: Optional[int] = None
    num_partitions: int = 4
    num_sub_vectors: Optional[int] = None
    metric: str = "cosine"
    replace: bool = True
    ef_construction: Optional[int] = None
    m: Optional[int] = None


class ScalarIndexSpec(BaseModel):
    index_type: Literal["BTREE", "BITMAP", "LABEL_LIST", "INVERTED", "NGRAM"]
    column: str
    replace: bool = True


class FTSIndexSpec(BaseModel):
    index_type: Literal["FTS"] = "FTS"
    column: str
    replace: bool = True
    language: str = "English"
    lower_case: bool = True
    stem: bool = True
    remove_stop_words: bool = True
    ascii_folding: bool = True


IndexSpec = Annotated[
    Union[VectorIndexSpec, ScalarIndexSpec, FTSIndexSpec],
    Field(discriminator="index_type"),
]


class LanceSinkOptions(BaseModel):
    catalog_name: str
    namespace: str
    table_name: str
    mode: Literal["overwrite", "append"] = "overwrite"
    indexes: list[IndexSpec] = []


def _parse_gs_uri(uri: str) -> tuple[str, str]:
    without_scheme = uri[len("gs://"):]
    bucket, _, prefix = without_scheme.partition("/")
    return bucket, prefix


def _find_lance_table_path(bucket: str, gcs_prefix: str, namespace: str, table_name: str) -> str:
    from google.cloud import storage
    client = storage.Client()
    iterator = client.list_blobs(bucket, prefix=f"{gcs_prefix}/", delimiter="/")
    prefixes = set()
    for page in iterator.pages:
        prefixes.update(page.prefixes)

    suffix = f"_{namespace}${table_name}"
    for prefix in prefixes:
        dir_name = prefix.rstrip("/").split("/")[-1]
        if dir_name.endswith(suffix):
            return f"gs://{bucket}/{prefix.rstrip('/')}"

    raise ValueError(
        f"Lance table not found: {namespace}.{table_name} in gs://{bucket}/{gcs_prefix}/"
    )


def _create_indexes(spark: SparkSession, options: LanceSinkOptions) -> None:
    import lancedb
    import pyarrow as pa
    from lancedb.table import LanceTable

    catalog_root = spark.conf.get(f"spark.sql.catalog.{options.catalog_name}.root")
    bucket, gcs_prefix = _parse_gs_uri(catalog_root)
    table_path = _find_lance_table_path(bucket, gcs_prefix, options.namespace, options.table_name)
    db = lancedb.connect(f"gs://{bucket}/{gcs_prefix}")
    tbl = LanceTable.open(db, options.table_name, location=table_path)

    for idx in options.indexes:
        try:
            if isinstance(idx, VectorIndexSpec):
                if idx.dimension is not None:
                    tbl.alter_columns({"path": idx.column, "data_type": pa.list_(pa.float32(), idx.dimension)})
                kwargs = {
                    "vector_column_name": idx.column,
                    "index_type": idx.index_type,
                    "num_partitions": idx.num_partitions,
                    "metric": idx.metric,
                    "replace": idx.replace,
                }
                if idx.num_sub_vectors is not None:
                    kwargs["num_sub_vectors"] = idx.num_sub_vectors
                if idx.ef_construction is not None:
                    kwargs["ef_construction"] = idx.ef_construction
                if idx.m is not None:
                    kwargs["m"] = idx.m
                tbl.create_index(**kwargs)
            elif isinstance(idx, FTSIndexSpec):
                tbl.create_fts_index(
                    idx.column,
                    replace=idx.replace,
                    language=idx.language,
                    lower_case=idx.lower_case,
                    stem=idx.stem,
                    remove_stop_words=idx.remove_stop_words,
                    ascii_folding=idx.ascii_folding,
                )
            else:
                tbl.create_scalar_index(idx.column, index_type=idx.index_type, replace=idx.replace)
        except Exception as exc:
            print(f"Index {idx.index_type} on {idx.column} skipped: {exc}")


class LanceSink(DataSink[LanceSinkOptions]):
    def write(self, df: DataFrame, options: LanceSinkOptions) -> None:
        spark = df.sparkSession
        full_table = f"{options.catalog_name}.{options.namespace}.{options.table_name}"
        spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {options.catalog_name}.{options.namespace}")
        writer = df.writeTo(full_table).using("lance")
        if options.mode == "overwrite":
            writer.createOrReplace()
        else:
            writer.append()
        if options.indexes:
            _create_indexes(spark, options)
