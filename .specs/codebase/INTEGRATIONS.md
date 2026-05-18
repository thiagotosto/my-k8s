# External Integrations

## Google Cloud Storage

**Purpose:** Armazenamento permanente de Lance tables (bronze/sandbox) e PDFs
**Implementation:** GCS Hadoop connector JAR (hadoop3-2.2.22) no Spark + google-cloud-storage Python lib
**Configuration:**
- `spark.hadoop.fs.gs.impl: com.google.cloud.hadoop.fs.gcs.GoogleHadoopFileSystem`
- `spark.hadoop.google.cloud.auth.type: APPLICATION_DEFAULT`
**Authentication:**
- Kind: ADC JSON file montado como Kubernetes Secret → `GOOGLE_APPLICATION_CREDENTIALS`
- GKE (target): Workload Identity — sem arquivo, ADC via metadata server

**Buckets:**
| Bucket | Purpose |
|--------|---------|
| thiagos-lake | Lance tables: bronze/, sandbox/ |
| juslake | PDFs de entrada (ex: thiago_x_meli.pdf) |
| juslake-terraform-state | TF state do workspace root |
| thiago-terraform-state | TF state do workspace apps/spark |

## Lance / LanceDB

**Purpose:** Formato de tabela vetorial colunar em GCS com suporte a vector search
**Spark integration:**
- `spark.sql.catalog.<name>: org.lance.spark.LanceNamespaceSparkCatalog`
- `spark.sql.catalog.<name>.impl: dir` (filesystem mode)
- `spark.sql.catalog.<name>.root: gs://thiagos-lake/<layer>`
- `spark.sql.extensions: org.lance.spark.extensions.LanceSparkSessionExtensions`
**Python integration:** `lancedb` para criar/abrir tabelas, `pylance` para operações de baixo nível
**Indexes:** IVF_PQ para vector search, FTS para full-text search

**Catalogs configurados:**
| Catalog | Root GCS |
|---------|----------|
| bronze | gs://thiagos-lake/bronze |
| sandbox | gs://thiagos-lake/sandbox |

## Trino Lance Connector

**Purpose:** Query SQL sobre Lance tables em GCS via Trino
**Implementation:** modules/trino/values.yaml — catálogos configurados via Helm values
**Authentication:** ADC JSON file em /etc/trino/gcs/ (Kind) → WI (target GKE)

## Hugging Face Hub (offline)

**Purpose:** Modelos de embedding pré-treinados
**Pattern:** Download único na primeira execução → cache em NFS PVC → `HF_HUB_OFFLINE=1` nos pods
**Models:**
| Model | Dim | Use |
|-------|-----|-----|
| all-MiniLM-L6-v2 | 384 | Text embeddings |
| ViT-B-32 (CLIP) | 512 | Image embeddings |

**Cache:** NFS PVC `spark-models-pvc` montado em `/opt/spark/models`, variável `HF_HOME=/opt/spark/models`

## Kubeflow Spark Operator

**Purpose:** Gerenciar ciclo de vida de SparkApplications no Kubernetes
**CRD:** `SparkApplication` (v1beta2)
**Namespace watch:** `spark-jobs` (configurado em Helm values)
**Webhook:** habilitado (mutation webhook para injeção de configs em driver/executor pods)

## Artifact Registry (target)

**Purpose:** Hospedar imagens Docker spark-lance-gcs e trino-lance-gcs
**Location:** us-central1-docker.pkg.dev/my-k8s-495416/my-k8s/
**Auth:** Node SA `{project_number}-compute@developer.gserviceaccount.com` com roles/artifactregistry.reader
