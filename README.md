# my-k8s

A local Kubernetes playground using [kind](https://kind.sigs.k8s.io/) and Terraform. Operators and Helm releases are managed as Terraform modules; application instances are defined as raw YAML and applied via the `kubectl` provider.

## Folder structure

```
.
├── main.tf          # Kind cluster definition and module calls
├── variables.tf
├── terraform.tfvars
├── modules/         # Operators and Helm installations
│   └── spark-operator/
└── apps/            # Application instances (SparkApplication, FlinkCluster, etc.)
    └── spark-pi/
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3.0
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Getting started

### 1. Create the cluster and install operators

```bash
terraform init
terraform apply
```

This creates a local kind cluster (`my-cluster`) with one control-plane and two worker nodes, then installs the enabled operators.

### 2. Deploy an app

Each app under `apps/` is an independent Terraform root module.

```bash
cd apps/spark-pi
terraform init
terraform apply
```

### 3. Destroy

```bash
# Remove the app first
cd apps/spark-pi
terraform destroy

# Then tear down the cluster
cd ../..
terraform destroy
```

## Modules

| Module | Description |
|---|---|
| `modules/spark-operator` | Installs the [Kubeflow Spark Operator](https://github.com/kubeflow/spark-operator) via Helm and provisions the `spark` ServiceAccount and RBAC needed by driver pods |

## Apps

| App | Description |
|---|---|
| `apps/spark-pi` | Runs the classic Spark Pi example as a `SparkApplication` |

## Variables

| Variable | Default | Description |
|---|---|---|
| `kubeconfig_path` | `~/.kube/config` | Path to the kubeconfig file |
| `kube_context` | `null` | Kubernetes context to use (defaults to current context) |
| `spark_operator` | `true` | Whether to install the Spark Operator |
