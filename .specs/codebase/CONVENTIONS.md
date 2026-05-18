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

- Cada módulo tem: `main.tf` (ou arquivos por recurso), `variables.tf`, `outputs.tf`, `providers.tf`
- apps/spark separa responsabilidades: `image.tf`, `script.tf`, `secret.tf`, `models.tf`, `providers.tf`
- Jobs Spark: um diretório por job com `job.py` + `spark.yaml`

## Comments

Comentários apenas quando o "porquê" não é óbvio. Sem comentários descritivos do que o código faz.
