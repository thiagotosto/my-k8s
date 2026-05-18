# Project Structure

**Root:** /home/ttosto/Documents/my-k8s

## Directory Tree

```
.
├── main.tf                    # Cluster (Kind/GKE) + module calls
├── variables.tf               # Root variables (feature flags, kubeconfig, GCP)
├── terraform.tfvars           # Runtime values
├── .terraform.lock.hcl        # Provider version hashes
├── modules/
│   ├── spark-operator/        # Kubeflow Spark Operator (Helm)
│   │   ├── operator.tf        # Namespace, SA spark, Helm release
│   │   ├── rbac.tf            # Role spark-driver + RoleBinding
│   │   ├── variables.tf       # spark_namespace, version, extra_helm_values
│   │   ├── outputs.tf
│   │   └── providers.tf
│   ├── trino/                 # Trino (Helm + custom image)
│   │   ├── main.tf            # Namespace, secret, Helm release
│   │   ├── image.tf           # Docker build + kind load (→ AR push no GKE)
│   │   ├── values.yaml        # Helm values template (Lance catalogs, GCS, image)
│   │   ├── variables.tf       # trino_namespace, version, credentials_path, etc.
│   │   ├── outputs.tf
│   │   └── providers.tf
│   └── gcs-bucket/            # Google Cloud Storage bucket provisioning
│       ├── main.tf
│       └── variables.tf
└── apps/
    ├── spark/                 # Spark jobs workspace (Terraform state separado)
    │   ├── providers.tf       # kubectl provider + TF backend GCS
    │   ├── image.tf           # Docker build + kind load (→ AR push no GKE)
    │   ├── script.tf          # Auto-discovery de jobs (fileset) + ConfigMaps + SparkApplications
    │   ├── secret.tf          # Kubernetes Secrets: gcs-adc, gcs-sa
    │   ├── models.tf          # NFS server pod/svc/pvc + model cache PVC RWM
    │   ├── variables.tf       # kubeconfig_path, kube_context, excluded_jobs
    │   ├── Dockerfile         # spark-lance-gcs:4.0.2 (Spark + Lance + GCS + ML)
    │   └── jobs/
    │       ├── hierarquical-cases/
    │       │   ├── job.py      # PySpark: PDF extraction + text embeddings + Lance
    │       │   └── spark.yaml  # SparkApplication manifest
    │       └── multimodal-products/
    │           ├── job.py      # PySpark: product catalog + text+image embeddings + Lance
    │           ├── spark.yaml
    │           └── credentials/
    │               └── my-k8s-495416-f42aa843ffe3.json  # GCS SA key (gitignored)
    └── playground/             # Python local (não K8s) — notebooks LanceDB/Trino
        └── lance.ipynb
```

## Module Organization

### modules/spark-operator
**Purpose:** Deploy Kubeflow spark-operator e criar namespace + RBAC
**Key files:** operator.tf (Helm release), rbac.tf (Role + RoleBinding para driver)

### modules/trino
**Purpose:** Deploy Trino com imagem customizada (Lance connector) e catalogs GCS
**Key files:** main.tf (Helm), image.tf (build), values.yaml (catalogs + auth)

### modules/gcs-bucket
**Purpose:** Provisionar GCS buckets com lifecycle protection
**Used twice in main.tf:** thiagos-lake (default) + juslake

### apps/spark
**Purpose:** Workloads Spark — imagem, jobs, secrets, NFS cache de modelos
**Special:** Workspace Terraform independente com estado GCS separado

## Where Things Live

**Cluster definition:** `main.tf` (root)
**Spark jobs scripts:** `apps/spark/jobs/<name>/job.py`
**SparkApplication manifests:** `apps/spark/jobs/<name>/spark.yaml`
**ML model cache:** NFS in-cluster, PVC `spark-models-pvc` em spark-jobs namespace
**Lance tables:** GCS — gs://thiagos-lake/bronze/ e gs://thiagos-lake/sandbox/
