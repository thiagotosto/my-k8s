# apps

Each subdirectory is an independent Terraform root that deploys application instances into the Kind cluster. Apps are decoupled from the cluster setup — you can apply or destroy them without touching the cluster itself.

## Layout

```
apps/
├── spark/       # PySpark jobs via the spark-operator
└── playground/  # Local Python environment (no Kubernetes resources)
```

## Conventions

- Apps use the `gavinbunney/kubectl` provider with `kubectl_manifest` to apply raw YAML resources.
- Each app has its own `providers.tf`, `variables.tf`, and `terraform.tfvars`.
- GCS Application Default Credentials are expected at `~/.config/gcloud/application_default_credentials.json`.

## Apps

| App | Description |
|---|---|
| [`spark`](spark/README.md) | PySpark jobs with a custom Spark image (Lance + GCS connectors + ML libraries); includes a multimodal product catalog job |
| [`playground`](playground/README.md) | Local Python/Jupyter environment for experimenting with LanceDB, Trino, and embedding models |

## Deploying

```bash
cd apps/<name>
terraform init
terraform apply
```

## Teardown

```bash
cd apps/<name>
terraform destroy
```
