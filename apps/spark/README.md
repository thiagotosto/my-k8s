# apps/spark

Deploys PySpark jobs onto the Kind cluster using the [Kubeflow Spark Operator](https://github.com/kubeflow/spark-operator). Each job lives in its own subdirectory under `jobs/` and is automatically discovered by Terraform.

## Structure

```
apps/spark/
├── Dockerfile          # Custom Spark image (lance + GCS connectors + ML libraries)
├── image.tf            # Builds the image and loads it into the Kind cluster
├── script.tf           # Auto-discovers jobs/ and creates ConfigMaps + SparkApplications
├── secret.tf           # GCS ADC credentials secret
├── models.tf           # NFS server, shared PVC, and one-time model download job
├── variables.tf
├── terraform.tfvars
└── jobs/
    └── multimodal-products/
        ├── job.py      # PySpark script
        └── spark.yaml  # SparkApplication manifest
```

## Custom image

Based on `apache/spark:4.0.2`, the image adds:

- **Lance Spark bundle** — `lance-spark-bundle-4.0_2.13` JAR for writing Lance tables
- **GCS connector** — `gcs-connector-hadoop3` shaded JAR for `gs://` filesystem access
- **Python libraries** — `torch` (CPU), `sentence-transformers`, `open-clip-torch`, `Pillow`, `lancedb`, `pandas`, `google-cloud-storage`

Build and load into Kind:

```bash
terraform apply   # image.tf triggers on Dockerfile changes
```

## Jobs

### multimodal-products

Generates a 30-row product catalog with 384-d text embeddings (`all-MiniLM-L6-v2`) and 512-d image embeddings (`CLIP ViT-B-32`), then writes the table to `gs://<GCS_BUCKET>/bronze/multimodal_products` as a Lance dataset and creates IVF_PQ vector indexes.

| Env var | Value |
|---|---|
| `GCS_BUCKET` | `thiagos-lake` |
| `GOOGLE_APPLICATION_CREDENTIALS` | `/var/secrets/google/application_default_credentials.json` |
| `HF_HOME` | `/opt/spark/models` |
| `TORCH_HOME` | `/opt/spark/models/torch` |

## Model cache (NFS PVC)

Embedding models are too large to download at runtime inside executor pods. `models.tf` sets up a shared volume:

1. **NFS server** — single-pod deployment backed by a 5 Gi RWO PVC, serves `/exports` over NFS.
2. **`spark-models-pv/pvc`** — NFS-backed PV/PVC with `ReadWriteMany` so all driver and executor pods (across both worker nodes) can mount it concurrently.
3. **`download-models` Job** — runs once at `terraform apply` using the custom Spark image; downloads `all-MiniLM-L6-v2` and `CLIP ViT-B-32` into the PVC and writes a `.downloaded` marker for idempotency.

## GCS credentials

`secret.tf` reads `~/.config/gcloud/application_default_credentials.json` and creates a Kubernetes Secret `gcs-adc` in the `spark-jobs` namespace. Run `gcloud auth application-default login` before applying.

## Variables

| Variable | Default | Description |
|---|---|---|
| `kubeconfig_path` | `~/.kube/config` | Path to the kubeconfig file |
| `kube_context` | `kind-my-cluster` | Kubernetes context |
| `excluded_jobs` | `[]` | Job names to skip without deleting their directories |

## Deploying

```bash
cd apps/spark
terraform init
terraform apply
```

On first apply Terraform will:
1. Build and load the custom Docker image into Kind.
2. Stand up the NFS server and pre-download the embedding models (~5–10 min).
3. Apply ConfigMaps and SparkApplications for every job in `jobs/`.

## Adding a new job

1. Create `jobs/<job-name>/job.py` and `jobs/<job-name>/spark.yaml`.
2. Name the ConfigMap reference in `spark.yaml` as `spark-<job-name>-script`.
3. Run `terraform apply` — `script.tf` picks it up automatically.

## Checking job logs

```bash
kubectl logs -n spark-jobs spark-<job-name>-driver --follow
```
