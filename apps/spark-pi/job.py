import os
from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, FloatType

spark = (
    SparkSession.builder
    .appName("spark-lance-gcs")
    .getOrCreate()
)

schema = StructType([
    StructField("id",       IntegerType(), False),
    StructField("name",     StringType(),  True),
    StructField("score",    FloatType(),   True),
    StructField("category", StringType(),  True),
])

data = [
    (1, "alice", 1.23, "A"),
    (2, "bob",   4.56, "B"),
    (3, "carol", 7.89, "A"),
    (4, "dave",  0.12, "C"),
    (5, "eve",   3.45, "B"),
]

df = spark.createDataFrame(data, schema)
df.show()

bucket = os.environ["GCS_BUCKET"]
output_path = f"gs://{bucket}/bronze/sample-table"

spark.sql("CREATE NAMESPACE IF NOT EXISTS lance.bronze")
df.writeTo("lance.bronze.`sample-table`").createOrReplace()

print(f"Wrote {df.count()} rows to Lance table at {output_path}")
spark.stop()
