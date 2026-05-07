import os
import pandas as pd
from pyspark.sql import SparkSession
from pyspark.sql.functions import pandas_udf, col, concat_ws, lit
from pyspark.sql.types import (
    StructType, StructField, StringType, IntegerType, FloatType, ArrayType,
)

# Module-level model caches — initialized once per executor process.
_text_model = None
_clip_model = None
_clip_tokenizer = None


def _get_text_model():
    global _text_model
    if _text_model is None:
        from sentence_transformers import SentenceTransformer
        _text_model = SentenceTransformer("all-MiniLM-L6-v2")
    return _text_model


def _get_clip():
    global _clip_model, _clip_tokenizer
    if _clip_model is None:
        import open_clip
        _clip_model, _, _ = open_clip.create_model_and_transforms(
            "ViT-B-32", pretrained="openai"
        )
        _clip_model.eval()
        _clip_tokenizer = open_clip.get_tokenizer("ViT-B-32")
    return _clip_model, _clip_tokenizer


@pandas_udf(ArrayType(FloatType()))
def encode_text(texts: pd.Series) -> pd.Series:
    """384-d L2-normalized text embeddings via sentence-transformers."""
    model = _get_text_model()
    vecs = model.encode(texts.tolist(), normalize_embeddings=True)
    return pd.Series([v.tolist() for v in vecs])


@pandas_udf(ArrayType(FloatType()))
def encode_image(image_descs: pd.Series) -> pd.Series:
    """
    512-d L2-normalized CLIP embeddings.

    Uses CLIP's text encoder on a descriptive string that represents the image
    (e.g. "product photo red running shoes"). In production, replace with CLIP's
    vision encoder fed actual image bytes downloaded from GCS.
    """
    import torch
    model, tokenizer = _get_clip()
    tokens = tokenizer(image_descs.tolist())
    with torch.no_grad():
        vecs = model.encode_text(tokens)
        vecs = vecs / vecs.norm(dim=-1, keepdim=True)
    return pd.Series([v.cpu().tolist() for v in vecs])


CATALOG = [
    # id, name, description, category, price, image_desc
    (1,  "Wireless Headphones",     "Over-ear headphones with 30h battery and noise cancellation",          "Electronics", 199.99, "product photo over-ear headphones black electronics"),
    (2,  "4K Smart TV",             "Ultra HD display with built-in streaming apps and HDR support",         "Electronics", 549.99, "product photo 4K smart television screen electronics"),
    (3,  "Gaming Keyboard",         "RGB backlit keyboard with tactile switches for competitive gaming",     "Electronics",  89.99, "product photo mechanical keyboard RGB lights electronics"),
    (4,  "Smartphone Pro",          "Flagship phone with triple camera system and all-day battery",          "Electronics", 999.99, "product photo smartphone black touchscreen electronics"),
    (5,  "Wireless Earbuds",        "Compact earbuds with 24h total battery and water resistance",           "Electronics",  79.99, "product photo wireless earbuds white case electronics"),
    (6,  "Running Shoes",           "Lightweight breathable trainers with cushioned midsole",                "Sports",       89.99, "product photo running shoes athletic footwear sports"),
    (7,  "Yoga Mat",                "Non-slip 6mm thick mat with carrying strap for yoga and pilates",       "Sports",       39.99, "product photo yoga mat purple exercise sports"),
    (8,  "Adjustable Dumbbells",    "Space-saving dumbbells adjustable from 5 to 52.5 lb",                  "Sports",      299.99, "product photo adjustable dumbbells weight training sports"),
    (9,  "Cycling Helmet",          "Aerodynamic road helmet with MIPS protection and ventilation",          "Sports",       79.99, "product photo bicycle helmet safety sports"),
    (10, "Foam Roller",             "High-density EVA foam roller for muscle recovery and stretching",       "Sports",       24.99, "product photo foam roller exercise recovery sports"),
    (11, "Organic Cotton T-Shirt",  "Breathable 100% organic cotton tee available in 12 colors",             "Clothing",     29.99, "product photo cotton t-shirt white apparel clothing"),
    (12, "Slim Fit Jeans",          "Classic 5-pocket denim in slim fit cut, sustainable fabric",            "Clothing",     59.99, "product photo slim fit jeans denim blue clothing"),
    (13, "Hiking Jacket",           "3-layer waterproof shell jacket, windproof for all weather",            "Clothing",    149.99, "product photo waterproof hiking jacket green outdoor clothing"),
    (14, "Wool Beanie",             "Merino wool knit hat, warm and itch-free for cold weather",             "Clothing",     24.99, "product photo wool beanie winter hat gray clothing"),
    (15, "Athletic Shorts",         "Quick-dry 7-inch shorts with built-in liner for athletic training",     "Clothing",     34.99, "product photo athletic shorts black sportswear clothing"),
    (16, "Python Crash Course",     "Beginner-friendly Python programming guide with real project examples", "Books",        39.99, "product photo Python programming book cover"),
    (17, "Deep Learning PyTorch",   "Hands-on guide to building neural networks with PyTorch",               "Books",        49.99, "product photo deep learning AI book cover"),
    (18, "The Art of War",          "Classic strategic treatise, translated and fully annotated",            "Books",        12.99, "product photo ancient strategy philosophy book cover"),
    (19, "Atomic Habits",           "Proven framework for building good habits and breaking bad ones",        "Books",        18.99, "product photo self-improvement habits book cover"),
    (20, "Clean Code",              "Guide to writing readable, maintainable, and professional software",    "Books",        44.99, "product photo software engineering clean code book cover"),
    (21, "Espresso Machine",        "15-bar semi-automatic espresso maker with integrated milk frother",     "Kitchen",     249.99, "product photo espresso coffee machine silver kitchen"),
    (22, "Cast Iron Skillet",       "Pre-seasoned 12-inch skillet for stovetop and oven cooking",           "Kitchen",      39.99, "product photo cast iron skillet black cookware kitchen"),
    (23, "High-Speed Blender",      "1200W blender for smoothies, soups, and nut butters",                  "Kitchen",      79.99, "product photo high-speed blender appliance kitchen"),
    (24, "Digital Air Fryer",       "6-quart XL air fryer with 8 preset cooking programs",                  "Kitchen",      89.99, "product photo digital air fryer black kitchen appliance"),
    (25, "Bamboo Cutting Board",    "Eco-friendly 3-piece cutting board set with juice grooves",             "Kitchen",      34.99, "product photo bamboo cutting board natural kitchen"),
    (26, "Whey Protein Powder",     "25g protein per serving, chocolate flavor, 5lb tub",                   "Nutrition",    49.99, "product photo protein powder tub chocolate supplement nutrition"),
    (27, "Fish Oil Omega-3",        "High-potency 1000mg omega-3 capsules for heart and brain health",      "Nutrition",    19.99, "product photo fish oil omega-3 capsules supplement nutrition"),
    (28, "Collagen Peptides",       "Grass-fed bovine collagen for skin, hair, and joint support",           "Nutrition",    29.99, "product photo collagen peptides powder supplement nutrition"),
    (29, "Daily Multivitamin",      "Complete daily multivitamin with 23 essential vitamins and minerals",   "Nutrition",    14.99, "product photo multivitamin tablets bottle supplement nutrition"),
    (30, "Pre-Workout Energy",      "Caffeine-free pre-workout with beta-alanine and citrulline",            "Nutrition",    34.99, "product photo pre-workout supplement powder nutrition"),
]

SCHEMA = StructType([
    StructField("id",          IntegerType(), False),
    StructField("name",        StringType(),  True),
    StructField("description", StringType(),  True),
    StructField("category",    StringType(),  True),
    StructField("price",       FloatType(),   True),
    StructField("image_desc",  StringType(),  True),
])


def create_vector_indexes(bucket: str, gcs_creds: str) -> None:
    """Find the lance-spark table on GCS and create IVF_PQ vector indexes."""
    from google.cloud import storage as gcs
    import lance

    client = gcs.Client()
    bucket_client = client.bucket(bucket)
    blobs = list(bucket_client.list_blobs(prefix="", delimiter="/"))
    table_dir = None
    for prefix in blobs.prefixes:
        if "bronze" in prefix and "multimodal" in prefix:
            table_dir = f"gs://{bucket}/{prefix.rstrip('/')}"
            break

    if not table_dir:
        print("Warning: could not locate multimodal-catalog directory; skipping index creation")
        return

    print(f"Found table at: {table_dir}")
    dataset = lance.dataset(
        table_dir,
        storage_options={"google_application_credentials": gcs_creds},
    )
    for col_name, dim in [("text_embedding", 384), ("image_embedding", 512)]:
        # num_sub_vectors must divide the dimension evenly
        sub_vecs = 12 if dim == 384 else 16
        try:
            dataset.create_index(
                col_name,
                index_type="IVF_PQ",
                num_partitions=1,
                num_sub_vectors=sub_vecs,
                metric="cosine",
                replace=True,
            )
            print(f"Created IVF_PQ index on {col_name} ({dim}d)")
        except Exception as exc:
            print(f"Index creation skipped for {col_name} ({exc}); brute-force scan will be used")


def main():
    spark = (
        SparkSession.builder
        .appName("spark-lance-multimodal")
        .getOrCreate()
    )

    bucket = os.environ["GCS_BUCKET"]
    gcs_creds = os.environ["GOOGLE_APPLICATION_CREDENTIALS"]

    df = spark.createDataFrame(CATALOG, SCHEMA)

    df = df.withColumn(
        "image_uri",
        concat_ws("", lit(f"gs://{bucket}/images/"), col("id").cast(StringType()), lit(".jpg")),
    )

    print("Generating text embeddings (sentence-transformers all-MiniLM-L6-v2, 384d)...")
    df = df.withColumn("text_embedding", encode_text(col("description")))

    print("Generating image embeddings (CLIP ViT-B-32, 512d)...")
    df = df.withColumn("image_embedding", encode_image(col("image_desc")))

    df = df.drop("image_desc")
    df.show(5, truncate=60)

    spark.sql("CREATE NAMESPACE IF NOT EXISTS lance.bronze")
    df.writeTo("lance.bronze.multimodal_products").createOrReplace()

    count = spark.sql("SELECT COUNT(*) FROM lance.bronze.multimodal_products").first()[0]
    print(f"Wrote {count} rows to lance.bronze.multimodal_products")

    create_vector_indexes(bucket, gcs_creds)

    spark.stop()


if __name__ == "__main__":
    main()
