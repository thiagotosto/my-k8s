# Architecture

**Pattern:** Modular Terraform com dois workspaces independentes (root + apps/spark)

## High-Level Structure

```
Root Workspace (main.tf)
├── Kind cluster OU GKE cluster (condicional via cluster_type)
├── module spark-operator → namespace spark-jobs, K8s SA spark, Helm chart
├── module trino → namespace trino, imagem custom, Helm chart, secret GCS
└── module gcs-bucket → GCS buckets thiagos-lake e juslake

apps/spark Workspace (apps/spark/)
├── null_resource → docker build + kind load (imagem spark-lance-gcs)
├── kubectl_manifest → Kubernetes Secrets (gcs-adc, gcs-sa)
├── kubectl_manifest × N → ConfigMap por job (script Python)
├── kubectl_manifest × N → SparkApplication por job
└── kubectl_manifest → NFS server pod + PVC + PV (model cache RWM)
```

## Identified Patterns

### Auto-discovery de Spark jobs
**Location:** `apps/spark/script.tf`
`fileset()` escaneia `jobs/*/spark.yaml`, cria:
- ConfigMap `spark-<job-name>-script` com conteúdo do `job.py`
- `kubectl_manifest` para cada `SparkApplication`
`excluded_jobs` var controla jobs a pular sem deletar do filesystem.

### Imagem custom via null_resource
**Location:** `modules/trino/image.tf`, `apps/spark/image.tf`
`null_resource` com `triggers = { dockerfile_md5 = filemd5(...) }` → `docker build + kind load`.
Rebuild só ocorre quando Dockerfile muda. Precisa mudar para AR push no GKE.

### Feature flags via count
**Location:** `main.tf`
Módulos opcionais usam `count = var.feature_flag ? 1 : 0`.
Exemplos: `count = var.spark_operator ? 1 : 0`, `count = (var.gcs_bucket && var.trino) ? 1 : 0`.
Padrão a estender para `cluster_type`.

### Two Terraform Workspaces
Root cria infraestrutura (cluster, operators, Trino).
apps/spark gerencia workloads Spark com state GCS separado.
Integração via kubeconfig — apps/spark não conhece recursos do root via terraform.
Sequência obrigatória: root apply → gcloud get-credentials → apps/spark apply.

## Data Flow

```
job.py (PySpark)
  → SparkApplication CR em spark-jobs namespace
  → spark-operator cria driver pod + executor pods
  → GCS (lê/escreve Lance tables via hadoop-gcs connector)
  → NFS PVC /opt/spark/models (lê modelos sentence-transformers e CLIP offline)
  → Output: Lance table em gs://thiagos-lake/{bronze,sandbox}/default.<table_name>
```

## Kubernetes Namespaces

- `spark-jobs`: spark-operator, driver/executor pods, NFS server, GCS secrets
- `trino`: Trino coordinator + workers, GCS secret gcs-adc

## GCS Auth Flow (atual — Kind)

```
~/.config/gcloud/adc.json → Kubernetes Secret gcs-adc → mounted em /var/secrets/google/
→ GOOGLE_APPLICATION_CREDENTIALS=/var/secrets/google/application_default_credentials.json
→ GCS Hadoop connector e google-cloud-storage Python lib leem credenciais do arquivo
```

## GCS Auth Flow (target — GKE com Workload Identity)

```
K8s SA spark annotada com iam.gke.googleapis.com/gcp-service-account: gke-workloads@...
→ Pod inicia no GKE com GKE_METADATA mode no node pool
→ Metadata server 169.254.169.254 troca token K8s por access token GCP SA
→ Application Default Credentials detecta automaticamente (sem GOOGLE_APPLICATION_CREDENTIALS)
→ GCS Hadoop connector e google-cloud-storage usam ADC normalmente
```
