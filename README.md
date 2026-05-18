# my-k8s

A local Kubernetes playground using [Kind](https://kind.sigs.k8s.io/) and Terraform. Operators and Helm releases are managed as Terraform modules under `modules/`; application instances are independent Terraform roots under `apps/`.

## Structure

```
.
├── main.tf               # Kind cluster + module calls
├── variables.tf
├── terraform.tfvars
├── modules/              # Operators and Helm installations
│   ├── spark-operator/   # Kubeflow Spark Operator + RBAC
│   ├── trino/            # Trino with custom image (Lance + GCS connectors)
│   └── gcs-bucket/       # GCS bucket for data lake storage
└── apps/                 # Application instances (independent Terraform roots)
    ├── spark/            # PySpark jobs using the spark-operator
    └── playground/       # Local Python environment for experimentation
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3.0
- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker](https://docs.docker.com/get-docker/)
- [gcloud CLI](https://cloud.google.com/sdk/docs/install) with Application Default Credentials (`gcloud auth application-default login`)

## Getting started

### 1. Create the cluster and install operators

```bash
terraform init
terraform apply
```

Creates a Kind cluster (`my-cluster`) with 1 control-plane and 2 worker nodes, then installs the enabled operators and Helm releases.

### 2. Deploy an app

Each app is an independent Terraform root. See the app's own README for details.

```bash
cd apps/spark
terraform init
terraform apply
```

### 3. Destroy

```bash
# Remove apps first
cd apps/spark && terraform destroy && cd ../..

# Then tear down the cluster
terraform destroy
```

## Modules

| Module | Description |
|---|---|
| `modules/spark-operator` | [Kubeflow Spark Operator](https://github.com/kubeflow/spark-operator) via Helm; provisions the `spark` ServiceAccount and RBAC |
| `modules/trino` | [Trino](https://trino.io/) via Helm with a custom image that includes the Lance connector and GCS support |
| `modules/gcs-bucket` | GCS bucket provisioned via the Google provider for data lake storage |

## Apps

| App | Description |
|---|---|
| [`apps/spark`](apps/spark/README.md) | PySpark jobs running on the spark-operator; includes a multimodal product catalog job with vector embeddings |
| [`apps/playground`](apps/playground/README.md) | Local Python environment for experimenting with LanceDB, Trino, and embedding models |

## Variables

| Variable | Default | Description |
|---|---|---|
| `kubeconfig_path` | `~/.kube/config` | Path to the kubeconfig file |
| `kube_context` | `null` | Kubernetes context (defaults to current context) |
| `spark_operator` | `true` | Install the Spark Operator |
| `trino` | `true` | Install Trino |
| `gcs_bucket` | `true` | Provision the GCS data bucket (requires `trino = true`) |
