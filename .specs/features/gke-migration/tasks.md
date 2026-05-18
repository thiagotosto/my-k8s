# GKE Migration Tasks

**Spec:** `.specs/features/gke-migration/spec.md`
**Design:** `.specs/features/gke-migration/design.md`
**Status:** Approved — Pending Execution

---

## Execution Plan

### Phase 1: Foundation (Sequential)

```
T1 → T2 → T3 → T4 → T5 → T6
```

### Phase 2: Module Updates (Partial Parallel)

```
T6 complete, then:
  ├── T7   (spark-operator WI annotation)
  ├── T8 [P] (trino image.tf → AR)
  └── T9 [P] (trino values + WI)
```

### Phase 3: apps/spark Updates (Parallel)

```
T7, T8, T9 complete, then:
  ├── T10 [P] (spark image.tf → AR)
  ├── T11 [P] (models.tf storage class)
  ├── T12 [P] (providers/vars kube_context)
  └── T13 [P] (SparkApplication yamls)
```

### Phase 4: Cleanup (Sequential)

```
T13 complete → T14 → T15
```

---

## Task Breakdown

### T1: Criar `.specs/` structure
**What:** Criar todos os arquivos de documentação spec-driven
**Where:** `.specs/`
**Depends on:** None
**Requirement:** Todos os GKE-* IDs em spec.md

**Done when:**
- [x] `.specs/project/PROJECT.md` criado
- [x] `.specs/project/ROADMAP.md` criado
- [x] `.specs/project/STATE.md` criado
- [x] `.specs/codebase/STACK.md` criado
- [x] `.specs/codebase/ARCHITECTURE.md` criado
- [x] `.specs/codebase/CONVENTIONS.md` criado
- [x] `.specs/codebase/STRUCTURE.md` criado
- [x] `.specs/codebase/TESTING.md` criado
- [x] `.specs/codebase/INTEGRATIONS.md` criado
- [x] `.specs/codebase/CONCERNS.md` criado
- [x] `.specs/features/gke-migration/spec.md` criado
- [x] `.specs/features/gke-migration/design.md` criado
- [x] `.specs/features/gke-migration/tasks.md` criado
- [x] Gate: `find .specs -name "*.md" | wc -l` → 13

**Verify:** `find .specs -name "*.md" | sort`
**Tests:** none
**Gate:** quick
**Status:** ✅ COMPLETED

**Commit:** `docs: initialize spec-driven structure and GKE migration feature spec`

---

### T2: `main.tf` + `variables.tf` — cluster_type var + resources condicionais + providers
**What:** Adicionar `cluster_type` variable, tornar Kind e GKE resources condicionais, atualizar providers para auth condicional
**Where:** `main.tf`, `variables.tf`
**Depends on:** T1
**Requirement:** GKE-01, GKE-02, GKE-03, GKE-04

**Done when:**
- [ ] `variable "cluster_type"` com `validation { condition = contains(["gke","kind"], var.cluster_type) }` em `variables.tf`
- [ ] `variable "gcp_region"` (default `"us-central1"`) e `variable "gcp_zone"` (default `"us-central1-a"`) em `variables.tf`
- [ ] `kind_cluster.my-cluster` com `count = var.cluster_type == "kind" ? 1 : 0`
- [ ] `google_container_cluster.my_cluster` com `count = var.cluster_type == "gke" ? 1 : 0` e `workload_identity_config`
- [ ] `google_container_node_pool.system` (min=1, max=3, e2-standard-4, GKE_METADATA) com `count = var.cluster_type == "gke" ? 1 : 0`
- [ ] `google_container_node_pool.spark` (min=0, max=10, label pool=spark, taint pool=spark:NoSchedule, GKE_METADATA) com `count = var.cluster_type == "gke" ? 1 : 0`
- [ ] `data "google_client_config" "default" {}` adicionado
- [ ] `locals { gke_endpoint, gke_ca_cert }` usando `try()` para valores condicionais
- [ ] Provider `kubernetes` com auth condicional (token GKE ou kubeconfig Kind)
- [ ] Provider `helm` com auth condicional (token GKE ou kubeconfig Kind)
- [ ] Variáveis `kubeconfig_path` e `kube_context` mantidas em `variables.tf`
- [ ] Gate kind: `terraform validate` passa sem flags
- [ ] Gate gke: `terraform validate -var cluster_type=gke` passa

**Verify:**
```bash
terraform validate
terraform validate -var cluster_type=gke
terraform plan -var cluster_type=kind | grep "kind_cluster"            # deve aparecer
terraform plan -var cluster_type=gke | grep "google_container_cluster" # deve aparecer
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(infra): add cluster_type variable to switch between Kind and GKE`

---

### T3: `main.tf` — Artifact Registry + IAM
**What:** Adicionar AR repository e IAM para pull de imagens no GKE
**Where:** `main.tf`
**Depends on:** T2
**Requirement:** GKE-05, GKE-06

**Done when:**
- [ ] `data "google_project" "default" {}` adicionado
- [ ] `google_artifact_registry_repository.my_k8s` com `count = var.cluster_type == "gke" ? 1 : 0`, location `var.gcp_region`, format `"DOCKER"`, repository_id `"my-k8s"`
- [ ] `google_project_iam_member.ar_reader` com role `roles/artifactregistry.reader`, member `serviceAccount:${data.google_project.default.number}-compute@developer.gserviceaccount.com`, `count = var.cluster_type == "gke" ? 1 : 0`
- [ ] Gate: `terraform validate -var cluster_type=gke` passa

**Verify:**
```bash
terraform validate -var cluster_type=gke
terraform plan -var cluster_type=gke | grep "artifact_registry_repository"
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(infra): add Artifact Registry repository and pull IAM (GKE mode only)`

---

### T4: `main.tf` — Workload Identity
**What:** Criar GCP SA, IAM bindings e WI bindings para Spark e Trino
**Where:** `main.tf`
**Depends on:** T2
**Requirement:** GKE-07, GKE-08, GKE-09

**Done when:**
- [ ] `google_service_account.gke_workloads` (account_id: `"gke-workloads"`) com `count = var.cluster_type == "gke" ? 1 : 0`
- [ ] `google_project_iam_member.workloads_gcs` (role: `roles/storage.objectAdmin`, member: `serviceAccount:${google_service_account.gke_workloads[0].email}`) com `count = var.cluster_type == "gke" ? 1 : 0`
- [ ] `google_service_account_iam_member.spark_wi` (role: `roles/iam.workloadIdentityUser`, member: `serviceAccount:my-k8s-495416.svc.id.goog[spark-jobs/spark]`, depends_on: module.spark-operator) com `count = var.cluster_type == "gke" ? 1 : 0`
- [ ] `google_service_account_iam_member.trino_wi` (role: `roles/iam.workloadIdentityUser`, member: `serviceAccount:my-k8s-495416.svc.id.goog[trino/trino]`, depends_on: module.trino) com `count = var.cluster_type == "gke" ? 1 : 0`
- [ ] Gate: `terraform validate -var cluster_type=gke` passa
- [ ] Gate kind: `terraform validate` passa (count=0, sem criação)

**Verify:**
```bash
terraform validate
terraform validate -var cluster_type=gke
terraform plan -var cluster_type=gke | grep "google_service_account"
terraform plan -var cluster_type=gke | grep "service_account_iam_member"  # deve mostrar 2
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(infra): add Workload Identity GCP SA and K8s SA bindings (GKE mode only)`

---

### T5: `terraform.tfvars`
**What:** Adicionar `cluster_type = "kind"` (default seguro que não altera estado atual)
**Where:** `terraform.tfvars`
**Depends on:** T2

**Done when:**
- [ ] `cluster_type = "kind"` presente no arquivo
- [ ] `kubeconfig_path = "~/.kube/config"` mantido
- [ ] Gate: `terraform validate` passa

**Verify:** `grep cluster_type terraform.tfvars` → `cluster_type = "kind"`
**Tests:** none
**Gate:** quick
**Commit:** `chore(infra): add cluster_type to terraform.tfvars`

---

### T6: Root `.terraform.lock.hcl` — terraform init
**What:** Executar terraform init para atualizar lock file após mudanças nas variáveis/resources
**Where:** `.terraform.lock.hcl`
**Depends on:** T2, T5

**Done when:**
- [ ] `terraform init` executado sem erros
- [ ] Provider `justenwalker/kind` ainda presente no lock (não removido — ainda usado no mode kind)
- [ ] Gate kind: `terraform validate` passa
- [ ] Gate gke: `terraform validate -var cluster_type=gke` passa

**Verify:**
```bash
grep "justenwalker/kind" .terraform.lock.hcl  # deve existir
terraform validate
terraform validate -var cluster_type=gke
```
**Tests:** none
**Gate:** quick
**Commit:** `chore(infra): refresh terraform lock after dual-mode cluster changes`

---

### T7: `modules/spark-operator/operator.tf` + `variables.tf` — WI annotation
**What:** Adicionar suporte a WI annotation no K8s SA spark via variável
**Where:** `modules/spark-operator/operator.tf`, `modules/spark-operator/variables.tf`, `main.tf`
**Depends on:** T4
**Requirement:** GKE-08

**Done when:**
- [ ] `variable "workload_identity_sa_email"` (type string, default `""`) em `modules/spark-operator/variables.tf`
- [ ] `kubernetes_service_account.spark` em `operator.tf` com `annotations = var.workload_identity_sa_email != "" ? { "iam.gke.googleapis.com/gcp-service-account" = var.workload_identity_sa_email } : {}`
- [ ] Module call em `main.tf` atualizado com `workload_identity_sa_email = try(google_service_account.gke_workloads[0].email, "")`
- [ ] Gate kind: `terraform validate` passa (email vazio, sem annotation)
- [ ] Gate gke: `terraform validate -var cluster_type=gke` passa (email preenchido, annotation presente)

**Verify:**
```bash
terraform validate
terraform validate -var cluster_type=gke
# Após apply no GKE:
kubectl get serviceaccount spark -n spark-jobs -o jsonpath='{.metadata.annotations}'
# deve conter iam.gke.googleapis.com/gcp-service-account
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(spark-operator): add Workload Identity annotation to spark ServiceAccount`

---

### T8 [P]: `modules/trino/image.tf` — kind load → AR push
**What:** Substituir `kind load docker-image` por `docker push` para Artifact Registry
**Where:** `modules/trino/image.tf`, `modules/trino/variables.tf`
**Depends on:** T3
**Requirement:** GKE-05

**Done when:**
- [ ] `variable "ar_repository"` (default `"us-central1-docker.pkg.dev/my-k8s-495416/my-k8s"`) em `modules/trino/variables.tf`
- [ ] `null_resource.trino_custom_image` provisioner: `docker build -t ${var.ar_repository}/trino-lance-gcs:476-v0.2.2 ${path.module} && docker push ${var.ar_repository}/trino-lance-gcs:476-v0.2.2`
- [ ] `kind load docker-image` completamente removido
- [ ] Trigger mantido: `dockerfile_md5 = filemd5("${path.module}/Dockerfile")`
- [ ] Gate: `terraform validate` passes (módulo trino)

**Verify:**
```bash
terraform validate
# Após apply:
gcloud artifacts docker images list us-central1-docker.pkg.dev/my-k8s-495416/my-k8s \
  --filter="tags:476-v0.2.2" --project=my-k8s-495416
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(trino): replace kind image load with Artifact Registry push`

---

### T9 [P]: `modules/trino/values.yaml` + `variables.tf` + `main.tf` — imagem AR + WI
**What:** Atualizar imagem Trino para AR, adicionar WI SA annotation, remover GCS credentials file
**Where:** `modules/trino/values.yaml`, `modules/trino/variables.tf`, `main.tf`
**Depends on:** T4
**Requirement:** GKE-09

**Done when:**
- [ ] `image.repository` em `values.yaml` → `us-central1-docker.pkg.dev/my-k8s-495416/my-k8s/trino-lance-gcs`
- [ ] `variable "workload_identity_sa_email"` (default `""`) em `modules/trino/variables.tf`
- [ ] WI annotation em `values.yaml` via `serviceAccount.annotations` (condicional ao email não vazio — via Helm set ou template logic)
- [ ] `gcsCredentials` removido do `values.yaml` (WI usa ADC automaticamente)
- [ ] Volume e volumeMount do secret `gcs-adc` removidos do `values.yaml` (Trino não monta mais JSON)
- [ ] Module call em `main.tf` atualizado com `workload_identity_sa_email = try(google_service_account.gke_workloads[0].email, "")`
- [ ] Gate: `terraform validate -var cluster_type=gke` passa

**Verify:**
```bash
terraform validate -var cluster_type=gke
# Após apply no GKE:
kubectl get serviceaccount trino -n trino -o jsonpath='{.metadata.annotations}'
# deve conter iam.gke.googleapis.com/gcp-service-account
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(trino): update image to AR, add WI SA annotation, remove GCS secret mount`

---

### T10 [P]: `apps/spark/image.tf` — kind load → AR push
**What:** Substituir `kind load docker-image` por `docker push` para Artifact Registry
**Where:** `apps/spark/image.tf`, `apps/spark/variables.tf`
**Depends on:** T3
**Requirement:** GKE-05

**Done when:**
- [ ] `variable "ar_repository"` (default `"us-central1-docker.pkg.dev/my-k8s-495416/my-k8s"`) em `apps/spark/variables.tf`
- [ ] `null_resource.spark_custom_image` provisioner: `docker build --pull=false -t ${var.ar_repository}/spark-lance-gcs:4.0.2 ${path.module} && docker push ${var.ar_repository}/spark-lance-gcs:4.0.2`
- [ ] `kind load docker-image spark-lance-gcs:4.0.2 --name my-cluster` removido
- [ ] Trigger mantido: `dockerfile_md5 = filemd5("${path.module}/Dockerfile")`
- [ ] Gate: `terraform validate` passa em `apps/spark/`

**Verify:**
```bash
cd apps/spark && terraform validate
# Após apply:
gcloud artifacts docker images list us-central1-docker.pkg.dev/my-k8s-495416/my-k8s \
  --filter="tags:4.0.2" --project=my-k8s-495416
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(spark): replace kind image load with Artifact Registry push`

---

### T11 [P]: `apps/spark/models.tf` — storage class para GKE
**What:** Atualizar storage class do PVC do NFS server de "standard" para "standard-rwo"
**Where:** `apps/spark/models.tf`
**Depends on:** None (mudança independente)
**Requirement:** GKE-12

**Done when:**
- [ ] PVC `nfs-server-storage`: `storageClassName = "standard-rwo"` (era `"standard"`)
- [ ] Gate: `terraform validate` passa em `apps/spark/`

**Verify:**
```bash
cd apps/spark && terraform validate
# Após apply no GKE:
kubectl get pvc nfs-server-storage -n spark-jobs -o jsonpath='{.status.phase}'
# deve retornar "Bound"
kubectl get pvc nfs-server-storage -n spark-jobs -o jsonpath='{.spec.storageClassName}'
# deve retornar "standard-rwo"
```
**Tests:** none
**Gate:** quick
**Commit:** `fix(spark): update NFS PVC storage class to standard-rwo for GKE`

---

### T12 [P]: `apps/spark/providers.tf` + `apps/spark/variables.tf` — kube_context GKE
**What:** Atualizar default de kube_context para contexto GKE
**Where:** `apps/spark/providers.tf`, `apps/spark/variables.tf`
**Depends on:** None (mudança de default independente)

**Done when:**
- [ ] `kube_context` default em `variables.tf` → `"gke_my-k8s-495416_us-central1-a_my-cluster"`
- [ ] `ar_repository` variable adicionada se não existe ainda (default: `"us-central1-docker.pkg.dev/my-k8s-495416/my-k8s"`)
- [ ] Gate: `terraform validate` passa em `apps/spark/`

**Verify:**
```bash
cd apps/spark && terraform validate
grep "kube_context" apps/spark/variables.tf | grep "default"
# deve mostrar o contexto GKE
```
**Tests:** none
**Gate:** quick
**Commit:** `fix(spark): update default kube_context to GKE cluster context`

---

### T13 [P]: SparkApplication manifests — imagem AR + node pool + remover GCS secrets
**What:** Atualizar ambos os spark.yaml com imagem AR, nodeSelector/tolerations para pool spark, remover dependências de GCS secret
**Where:** `apps/spark/jobs/hierarquical-cases/spark.yaml`, `apps/spark/jobs/multimodal-products/spark.yaml`
**Depends on:** T7 (WI annotation no SA spark deve estar configurado antes de remover secrets)
**Requirement:** GKE-05, GKE-10, GKE-11

**Done when (ambos os arquivos):**
- [ ] `spec.image:` → `"us-central1-docker.pkg.dev/my-k8s-495416/my-k8s/spark-lance-gcs:4.0.2"`
- [ ] `driver.nodeSelector: { pool: spark }` presente
- [ ] `driver.tolerations: [{ key: pool, operator: Equal, value: spark, effect: NoSchedule }]` presente
- [ ] `executor.nodeSelector: { pool: spark }` presente
- [ ] `executor.tolerations: [{ key: pool, operator: Equal, value: spark, effect: NoSchedule }]` presente
- [ ] Volume `gcs-adc` removido de `spec.volumes`
- [ ] VolumeMount `gcs-adc` removido de `driver.volumeMounts`
- [ ] VolumeMount `gcs-adc` removido de `executor.volumeMounts`
- [ ] Env var `GOOGLE_APPLICATION_CREDENTIALS` removida de driver e executor
- [ ] `HF_HOME`, `TORCH_HOME`, `HF_HUB_OFFLINE`, `GCS_BUCKET` e outros envs mantidos
- [ ] Volume e mount de `models` (PVC) mantidos
- [ ] Volume e mount de `script` (ConfigMap) mantidos
- [ ] Gate: `kubectl apply --dry-run=client -f <yaml>` passa para ambos

**Verify:**
```bash
kubectl apply --dry-run=client -f apps/spark/jobs/hierarquical-cases/spark.yaml
kubectl apply --dry-run=client -f apps/spark/jobs/multimodal-products/spark.yaml
# Após apply e execução do job no GKE:
kubectl get pod -n spark-jobs -l spark-role=driver -o wide
# deve mostrar pod em nó com label pool=spark
```
**Tests:** none
**Gate:** YAML dry-run
**Commit:** `feat(spark): update SparkApplication manifests for GKE (AR image, node pool, WI auth)`

---

### T14: `apps/spark/secret.tf` — remover GCS secrets
**What:** Remover recursos de GCS credential secrets (substituídos por Workload Identity)
**Where:** `apps/spark/secret.tf`
**Depends on:** T7 (WI configurado), T13 (manifests não referenciam mais os secrets)

**Done when:**
- [ ] `kubectl_manifest.gcs_adc_secret` removido
- [ ] `kubectl_manifest.gcs_sa_secret` removido
- [ ] Gate: `terraform validate` passa em `apps/spark/`

**Verify:**
```bash
cd apps/spark && terraform validate
terraform plan  # deve mostrar -2 resources (secrets destruídos)
# Após apply no GKE, confirmar que Spark job ainda funciona:
kubectl get sparkapplication -n spark-jobs -w
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(spark): remove GCS ADC secrets replaced by Workload Identity`

---

### T15: `apps/spark/.terraform.lock.hcl` — terraform init
**What:** Refresh do lock file após mudanças de providers/variáveis no workspace apps/spark
**Where:** `apps/spark/.terraform.lock.hcl`
**Depends on:** T10, T11, T12, T14

**Done when:**
- [ ] `terraform init` executado sem erros em `apps/spark/`
- [ ] Gate: `terraform validate` passa em `apps/spark/`

**Verify:**
```bash
cd apps/spark && terraform init && terraform validate
```
**Tests:** none
**Gate:** quick
**Commit:** `chore(spark): refresh terraform lock after GKE migration`

---

## Task Granularity Check

| Task | Scope | Status |
|------|-------|--------|
| T1: specs structure | 13 arquivos docs | ✅ Granular |
| T2: cluster_type var + resources | 2 arquivos, 1 tema coeso | ✅ OK |
| T3: AR repository + IAM | 1 arquivo, 2 resources | ✅ Granular |
| T4: WI SA + IAM bindings | 1 arquivo, 4 resources WI | ✅ Granular (WI = 1 feature) |
| T5: terraform.tfvars | 1 arquivo, 1 linha | ✅ Granular |
| T6: root lock file | 1 arquivo, 1 comando | ✅ Granular |
| T7: spark-operator WI annotation | 2 arquivos módulo + 1 module call | ✅ OK |
| T8: trino image.tf | 2 arquivos, 1 feature | ✅ Granular |
| T9: trino values + WI | 3 arquivos, 1 feature (imagem+WI) | ✅ OK |
| T10: spark image.tf | 2 arquivos, 1 feature | ✅ Granular |
| T11: models.tf storage class | 1 arquivo, 1 valor | ✅ Granular |
| T12: providers + kube_context | 2 arquivos, 1 feature | ✅ OK |
| T13: SparkApplication yamls | 2 arquivos, mesmo padrão | ✅ OK |
| T14: secret.tf cleanup | 1 arquivo, 2 resources removidos | ✅ Granular |
| T15: apps/spark lock | 1 arquivo, 1 comando | ✅ Granular |

---

## Diagram-Definition Cross-Check

| Task | Depends On (body) | Diagram Shows | Status |
|------|-------------------|---------------|--------|
| T1 | None | Start Phase 1 | ✅ |
| T2 | T1 | T1 → T2 | ✅ |
| T3 | T2 | T2 → T3 | ✅ |
| T4 | T2 | T2 → T4 | ✅ |
| T5 | T2 | T4 → T5 | ✅ |
| T6 | T2, T5 | T5 → T6 | ✅ |
| T7 | T4 | T6 → T7 | ✅ |
| T8 [P] | T3 | T6 → T8 (paralelo) | ✅ |
| T9 [P] | T4 | T6 → T9 (paralelo) | ✅ |
| T10 [P] | T3 | T7,T8,T9 → T10 | ✅ |
| T11 [P] | None | T7,T8,T9 → T11 | ✅ |
| T12 [P] | None | T7,T8,T9 → T12 | ✅ |
| T13 [P] | T7 | T7,T8,T9 → T13 | ✅ |
| T14 | T7, T13 | T13 → T14 | ✅ |
| T15 | T10, T11, T12, T14 | T14 → T15 | ✅ |

---

## Test Co-location Validation

| Task | Code Layer | Matrix Requires | Task Says | Status |
|------|-----------|-----------------|-----------|--------|
| T2 | Terraform module | none (validate) | none | ✅ |
| T3 | Terraform module | none (validate) | none | ✅ |
| T4 | Terraform module | none (validate) | none | ✅ |
| T7 | K8s SA annotation | none (dry-run validate) | none | ✅ |
| T8 | Docker image build | none (manual verify) | none | ✅ |
| T9 | Helm values | none (validate) | none | ✅ |
| T10 | Docker image build | none (manual verify) | none | ✅ |
| T11 | K8s manifest | none (validate) | none | ✅ |
| T13 | SparkApplication YAML | none (dry-run) | none + YAML gate | ✅ |
| T14 | K8s manifest | none (validate) | none | ✅ |
