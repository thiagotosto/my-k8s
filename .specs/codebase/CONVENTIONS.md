# Code Conventions

## Naming Conventions

**Terraform resources:** snake_case
- `kind_cluster.my-cluster`, `kubernetes_namespace.spark`, `helm_release.spark_operator`

**Terraform modules:** kebab-case
- `spark-operator`, `gcs-bucket`, `trino`

**Spark job directories:** kebab-case
- `hierarquical-cases`, `multimodal-products`

**Kubernetes resources:** kebab-case
- ConfigMap `spark-<job-name>-script`, Secret `gcs-adc`, SA `spark`

**Terraform variables:** snake_case com defaults explícitos
- `spark_operator`, `trino`, `gcs_bucket`, `kubeconfig_path`, `kube_context`

## Terraform Patterns

### Feature flags via count
```hcl
module "trino" {
  count  = var.trino ? 1 : 0
  source = "./modules/trino"
}
```
Módulos opcionais sempre usam `count`, nunca `for_each`.

### Extra Helm values como map(string)
```hcl
variable "extra_helm_values" {
  type    = map(string)
  default = {}
}
# Usado via:
set = [for k, v in var.extra_helm_values : { name = k, value = v }]
```

### Secrets sensíveis via sensitive_fields
```hcl
resource "kubectl_manifest" "gcs_adc_secret" {
  sensitive_fields = ["stringData"]
  yaml_body = yamlencode({ ... })
}
```

### null_resource para builds de imagem
Trigger em Dockerfile MD5 garante rebuild apenas quando necessário.
```hcl
triggers = { dockerfile_md5 = filemd5("${path.module}/Dockerfile") }
```

## Kubernetes / SparkApplication

### SparkApplication padrão
- `apiVersion: sparkoperator.k8s.io/v1beta2`
- `imagePullPolicy: IfNotPresent`
- `timeToLiveSeconds: 300` (cleanup automático)
- `restartPolicy.type: Never`
- GCS Hadoop connector config via `sparkConf`:
  - `spark.hadoop.google.cloud.auth.type: APPLICATION_DEFAULT`
  - `spark.sql.catalog.<name>: org.lance.spark.LanceNamespaceSparkCatalog`

### Resources padrão de jobs
- Driver: 1 core, 2-4GB memory
- Executor: 1 core, 3GB memory, 2 instâncias

## File Organization

### Module file convention

Modules split resources by **infrastructure concern** — each file owns one logical group.

**Always present:**
- `variables.tf` — all `variable` blocks
- `outputs.tf` — all `output` blocks
- `providers.tf` — `terraform {}` + `provider {}` blocks (when needed)
- `main.tf` — `locals {}` only; no resource definitions

**Concern files (create only when the module has those resources):**

| File | Resources |
|------|-----------|
| `image.tf` | `null_resource` Docker image builds |
| `rbac.tf` | `kubernetes_role`, `kubernetes_role_binding` |
| `secret.tf` | `kubernetes_secret` |
| `iam.tf` | GCP service accounts, IAM bindings (`*_iam_member`, `*_iam_binding`) |
| `pubsub.tf` | `google_pubsub_topic`, `google_pubsub_subscription` |
| `cloudrun.tf` | `google_cloud_run_v2_service` |
| `artifact_registry.tf` | `google_artifact_registry_repository` |
| `gcs.tf` | `google_storage_notification`, `google_storage_bucket` |
| `workloads.tf` | `kubernetes_deployment`, `kubernetes_manifest` (StatefulSets, etc.) |
| `services.tf` | `kubernetes_service` |
| `pv_pvc.tf` | `kubernetes_persistent_volume_claim`, `kubernetes_persistent_volume` |
| `namespace.tf` | `kubernetes_namespace` (standalone modules without an `operator.tf`) |

Existing examples in this repo:
- `spark-operator/` — `operator.tf` (namespace + SA + Helm release), `rbac.tf`
- `trino/` — `image.tf`; `main.tf` holds the sole Helm release (single-concern, acceptable)
- `apps/spark/` — `image.tf`, `secret.tf`, `script.tf`, `models.tf`

Do not create a file unless it contains at least one resource.

- Jobs Spark: um diretório por job com `job.py` + `spark.yaml`

## Comments

Comentários apenas quando o "porquê" não é óbvio. Sem comentários descritivos do que o código faz.
