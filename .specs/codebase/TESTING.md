# Testing Infrastructure

## Test Frameworks

Nenhum framework de testes automatizados. Validação é manual e baseada em comandos CLI.

## Test Organization

Não há diretório de testes. Validação ocorre durante/após `terraform apply` via kubectl e gsutil.

## Testing Patterns

### Terraform (Infra)
**Approach:** `terraform validate` para sintaxe + `terraform plan` para preview
**Commands:**
```bash
terraform validate
terraform plan -var cluster_type=gke   # preview sem apply
```

### Kubernetes (Workloads)
**Approach:** `kubectl apply --dry-run=client` para YAMLs, kubectl get/describe para estado
```bash
kubectl apply --dry-run=client -f apps/spark/jobs/<job>/spark.yaml
kubectl get sparkapplication -n spark-jobs -w
kubectl describe sparkapplication <name> -n spark-jobs
```

### Spark Jobs (Funcional)
**Approach:** Submissão manual do job + verificar SparkApplication status + output GCS
```bash
kubectl get sparkapplication -n spark-jobs spark-hierarquical-processes -o jsonpath='{.status.applicationState.state}'
# esperado: COMPLETED
gsutil ls gs://thiagos-lake/sandbox/default.hierarquical_cases/
```

### GCS Auth
```bash
kubectl exec -n spark-jobs <driver-pod> -- python3 -c "from google.cloud import storage; storage.Client().bucket('thiagos-lake').exists()"
```

## Test Coverage Matrix

| Layer | Required Test Type | Location Pattern | Command |
|-------|-------------------|-----------------|---------|
| Terraform modules | none (validate) | `modules/**/*.tf` | `terraform validate` |
| Root main.tf | none (validate + plan) | `main.tf` | `terraform validate && terraform plan` |
| SparkApplication YAML | none (dry-run) | `apps/spark/jobs/*/spark.yaml` | `kubectl apply --dry-run=client` |
| Spark job Python | none (manual submit) | `apps/spark/jobs/*/job.py` | Submissão manual |
| GCS output | none (manual verify) | GCS buckets | `gsutil ls gs://...` |

## Parallelism Assessment

| Test Type | Parallel-Safe? | Evidence |
|-----------|---------------|---------|
| terraform validate | Yes | Stateless, só lê arquivos |
| terraform plan | Yes (read-only mode) | Não altera estado |
| kubectl dry-run | Yes | Não cria recursos |
| SparkApplication submit | No | Usa cluster compartilhado, altera estado K8s |
| GCS verification | Yes | Somente leitura |

## Gate Check Commands

| Gate | Quando Usar | Command |
|------|------------|---------|
| Quick | Após mudanças Terraform | `terraform validate` |
| Full | Após mudanças que afetam cluster | `terraform validate && terraform plan` |
| YAML | Após mudanças em SparkApplication | `kubectl apply --dry-run=client -f <yaml>` |
| Job | Após mudanças em job.py | Submissão manual + verificar COMPLETED |
