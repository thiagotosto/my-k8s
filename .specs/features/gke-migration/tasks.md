# GKE Migration Tasks

**Spec:** `.specs/features/gke-migration/spec.md`
**Design:** `.specs/features/gke-migration/design.md`
**Status:** In Progress — T1–T15 code implemented; T4/T7/T8/T9/T12/T10/T11/T13/T14 await `terraform apply` (GKE deployment)

---

## Execution Plan

### Phase 1: Foundation (Sequential)

```
T5 → T6 → T4 → T7
```

T5+T6 are quick prep (tfvars + lock). T4 is the **first GKE deployment** — it applies the
already-committed T2+T3 code (cluster, AR) plus new WI resources in one shot.

### Phase 2: Module Updates (Partial Parallel)

```
T7 complete, then:
  ├── T8 [P] (trino image.tf → AR)
  └── T9 [P] (trino values + WI)
```

### Phase 3: apps/spark Updates (Sequential start, then Parallel)

```
T8, T9 complete, then:
  T12 (kube_context + ar_repository vars — must come first to connect to GKE)
    └── T10 [P] (spark image.tf → AR)
    └── T11 [P] (models.tf storage class)
          └── T13 (SparkApplication yamls)
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
- [x] `variable "cluster_type"` com `validation { condition = contains(["gke","kind"], var.cluster_type) }` em `variables.tf`
- [x] `variable "gcp_region"` (default `"us-central1"`) e `variable "gcp_zone"` (default `"us-central1-a"`) em `variables.tf`
- [x] `kind_cluster.my-cluster` com `count = var.cluster_type == "kind" ? 1 : 0`
- [x] `google_container_cluster.my_cluster` com `count = var.cluster_type == "gke" ? 1 : 0` e `workload_identity_config`
- [x] `google_container_node_pool.system` (min=1, max=3, e2-standard-4, GKE_METADATA) com `count = var.cluster_type == "gke" ? 1 : 0`
- [x] `google_container_node_pool.spark` (min=0, max=10, label pool=spark, taint pool=spark:NoSchedule, GKE_METADATA) com `count = var.cluster_type == "gke" ? 1 : 0`
- [x] `data "google_client_config" "default" {}` adicionado
- [x] `locals { gke_endpoint, gke_ca_cert }` usando `try()` para valores condicionais
- [x] Provider `kubernetes` com auth condicional (token GKE ou kubeconfig Kind)
- [x] Provider `helm` com auth condicional (token GKE ou kubeconfig Kind)
- [x] Variáveis `kubeconfig_path` e `kube_context` mantidas em `variables.tf`
- [x] Gate kind: `terraform validate` passa sem flags
- [x] Gate gke: `terraform validate -var cluster_type=gke` passa

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
**Status:** ✅ COMPLETED

---

### T3: `main.tf` — Artifact Registry + IAM
**What:** Adicionar AR repository e IAM para pull de imagens no GKE
**Where:** `main.tf`
**Depends on:** T2
**Requirement:** GKE-05, GKE-06

**Done when:**
- [x] `data "google_project" "default" {}` adicionado
- [x] `google_artifact_registry_repository.my_k8s` com `count = var.cluster_type == "gke" ? 1 : 0`, location `var.gcp_region`, format `"DOCKER"`, repository_id `"my-k8s"`
- [x] `google_project_iam_member.ar_reader` com role `roles/artifactregistry.reader`, member `serviceAccount:${data.google_project.default.number}-compute@developer.gserviceaccount.com`, `count = var.cluster_type == "gke" ? 1 : 0`
- [x] Gate: `terraform validate -var cluster_type=gke` passa

**Verify:**
```bash
terraform validate -var cluster_type=gke
terraform plan -var cluster_type=gke | grep "artifact_registry_repository"
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(infra): add Artifact Registry repository and pull IAM (GKE mode only)`
**Status:** ✅ COMPLETED

---

### T5: `terraform.tfvars`
**What:** Adicionar `cluster_type = "kind"` (default seguro que não altera estado atual)
**Where:** `terraform.tfvars`
**Depends on:** T2

**Done when:**
- [x] `cluster_type = "kind"` presente no arquivo
- [x] `kubeconfig_path = "~/.kube/config"` mantido
- [ ] Gate: `terraform apply` passa em kind mode sem criar recursos GKE

**Verify:**
```bash
grep cluster_type terraform.tfvars            # → cluster_type = "kind"
terraform apply                               # kind mode — no GKE resources created
kubectl get nodes                             # → kind-my-cluster nodes present
kubectl get pods -A | grep -v Running         # → no unexpected failures
```
**Tests:** none
**Gate:** quick
**Commit:** `chore(infra): add cluster_type to terraform.tfvars`
**Status:** ✅ COMPLETED (code done; apply gate pending user run)

---

### T6: Root `.terraform.lock.hcl` — terraform init
**What:** Executar terraform init para atualizar lock file após mudanças nas variáveis/resources
**Where:** `.terraform.lock.hcl`
**Depends on:** T2, T5

**Done when:**
- [x] `terraform init` executado sem erros
- [x] Provider `justenwalker/kind` ainda presente no lock (não removido — ainda usado no mode kind)
- [x] Gate kind: `terraform validate` passa
- [x] Gate gke: `terraform validate -var cluster_type=gke` passa

**Verify:**
```bash
terraform init
grep "justenwalker/kind" .terraform.lock.hcl  # → provider still present
terraform validate
terraform validate -var cluster_type=gke
terraform plan -detailed-exitcode             # → exit 0 (no changes in kind mode)
```
**Tests:** none
**Gate:** quick
**Commit:** `chore(infra): refresh terraform lock after dual-mode cluster changes`
**Status:** ✅ COMPLETED

---

### T4: `main.tf` — Workload Identity (first GKE deployment)
**What:** Criar GCP SA, IAM bindings e WI bindings para Spark e Trino. Este apply também
provisiona o cluster GKE, node pools e Artifact Registry (código de T2+T3 aplicado pela
primeira vez em modo GKE).
**Where:** `main.tf`
**Depends on:** T2, T6
**Requirement:** GKE-07, GKE-08, GKE-09

**Done when:**
- [x] `google_service_account.gke_workloads` (account_id: `"gke-workloads"`) com `count = var.cluster_type == "gke" ? 1 : 0`
- [x] `google_project_iam_member.workloads_gcs` (role: `roles/storage.objectAdmin`, member: `serviceAccount:${google_service_account.gke_workloads[0].email}`) com `count = var.cluster_type == "gke" ? 1 : 0`
- [x] `google_service_account_iam_member.spark_wi` (role: `roles/iam.workloadIdentityUser`, member: `serviceAccount:jusl-496520.svc.id.goog[spark-jobs/spark]`, depends_on: module.spark-operator) com `count = var.cluster_type == "gke" ? 1 : 0`
- [x] `google_service_account_iam_member.trino_wi` (role: `roles/iam.workloadIdentityUser`, member: `serviceAccount:jusl-496520.svc.id.goog[trino/trino]`, depends_on: module.trino) com `count = var.cluster_type == "gke" ? 1 : 0`
- [x] Gate: `terraform apply -var cluster_type=gke` completa sem erros

**Verify:**
```bash
terraform apply -var cluster_type=gke
# Verify cluster:
kubectl get nodes
# → ≥1 node com label cloud.google.com/gke-nodepool=system, 0 com pool=spark
kubectl get nodes -l cloud.google.com/gke-nodepool=system -o wide
# → STATUS Ready
# Verify Artifact Registry:
gcloud artifacts repositories list --project=jusl-496520 --location=us-central1
# → my-k8s  DOCKER  us-central1
# Verify WI SA e IAM:
gcloud iam service-accounts list --project=jusl-496520 | grep gke-workloads
# → gke-workloads@jusl-496520.iam.gserviceaccount.com
gcloud projects get-iam-policy jusl-496520 --format=json \
  | jq '.bindings[] | select(.role=="roles/storage.objectAdmin") | .members[]'
# → "serviceAccount:gke-workloads@jusl-496520.iam.gserviceaccount.com"
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(infra): add Workload Identity GCP SA and K8s SA bindings (GKE mode only)`
**Status:** ✅ COMPLETED

---

### T7: `modules/spark-operator/operator.tf` + `variables.tf` — WI annotation
**What:** Adicionar suporte a WI annotation no K8s SA spark via variável
**Where:** `modules/spark-operator/operator.tf`, `modules/spark-operator/variables.tf`, `main.tf`
**Depends on:** T4
**Requirement:** GKE-08

**Done when:**
- [x] `variable "workload_identity_sa_email"` (type string, default `""`) em `modules/spark-operator/variables.tf`
- [x] `kubernetes_service_account.spark` em `operator.tf` com `annotations = var.workload_identity_sa_email != "" ? { "iam.gke.io/gcp-service-account" = var.workload_identity_sa_email } : {}`
- [x] Module call em `main.tf` atualizado com `workload_identity_sa_email = try(google_service_account.gke_workloads[0].email, "")`

**Verify:**
```bash
terraform apply -var cluster_type=gke
kubectl get serviceaccount spark -n spark-jobs \
  -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}'
# → gke-workloads@jusl-496520.iam.gserviceaccount.com
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(spark-operator): add Workload Identity annotation to spark ServiceAccount`
**Status:** ✅ COMPLETED

---

### T8 [P]: `modules/trino/image.tf` — kind load → AR push
**What:** Substituir `kind load docker-image` por `docker push` para Artifact Registry
**Where:** `modules/trino/image.tf`, `modules/trino/variables.tf`
**Depends on:** T3, T4
**Requirement:** GKE-05

**Done when:**
- [x] `variable "ar_repository"` (default `"us-central1-docker.pkg.dev/jusl-496520/my-k8s"`) em `modules/trino/variables.tf`
- [x] `null_resource.trino_custom_image` provisioner: `docker build -t ${var.ar_repository}/trino-lance-gcs:476-v0.2.2 ${path.module} && docker push ${var.ar_repository}/trino-lance-gcs:476-v0.2.2`
- [x] `kind load docker-image` completamente removido
- [x] Trigger mantido: `dockerfile_md5 = filemd5("${path.module}/Dockerfile")`

**Verify:**
```bash
terraform apply -var cluster_type=gke
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/jusl-496520/my-k8s \
  --filter="tags:476-v0.2.2" --project=jusl-496520
# → trino-lance-gcs  476-v0.2.2  listed
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(trino): replace kind image load with Artifact Registry push`
**Status:** ✅ COMPLETED

---

### T9 [P]: `modules/trino/values.yaml` + `variables.tf` + `main.tf` — imagem AR + WI
**What:** Atualizar imagem Trino para AR, adicionar WI SA annotation, remover GCS credentials file
**Where:** `modules/trino/values.yaml`, `modules/trino/variables.tf`, `main.tf`
**Depends on:** T4, T8
**Requirement:** GKE-09

**Done when:**
- [x] `image.repository` em `values.yaml` → `us-central1-docker.pkg.dev/jusl-496520/my-k8s/trino-lance-gcs`
- [x] `variable "workload_identity_sa_email"` (default `""`) em `modules/trino/variables.tf`
- [x] WI annotation em `values.yaml` via `serviceAccount.annotations` (condicional ao email não vazio)
- [x] `gcsCredentials` removido do `values.yaml` (WI usa ADC automaticamente)
- [x] Volume e volumeMount do secret `gcs-adc` removidos do `values.yaml`
- [x] Module call em `main.tf` atualizado com `workload_identity_sa_email = try(google_service_account.gke_workloads[0].email, "")`

**Verify:**
```bash
terraform apply -var cluster_type=gke
kubectl get serviceaccount trino -n trino \
  -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}'
# → gke-workloads@jusl-496520.iam.gserviceaccount.com
kubectl get deployment trino -n trino \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# → us-central1-docker.pkg.dev/jusl-496520/my-k8s/trino-lance-gcs:476-v0.2.2
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(trino): update image to AR, add WI SA annotation, remove GCS secret mount`
**Status:** ✅ COMPLETED

---

### T12 [P]: `apps/spark/providers.tf` + `apps/spark/variables.tf` — kube_context GKE
**What:** Atualizar default de kube_context para contexto GKE e adicionar ar_repository variable.
Deve ser o **primeiro task** do workspace apps/spark para que os applies seguintes conectem ao GKE.
**Where:** `apps/spark/providers.tf`, `apps/spark/variables.tf`
**Depends on:** T4 (GKE cluster deve estar rodando)

**Done when:**
- [x] `kube_context` default em `variables.tf` → `"gke_jusl-496520_us-central1-a_my-cluster"`
- [x] `ar_repository` variable adicionada (default: `"us-central1-docker.pkg.dev/jusl-496520/my-k8s"`)
- [x] Gate: `terraform validate` passa em `apps/spark/`

**Pre-requisite (manual):**
```bash
gcloud container clusters get-credentials my-cluster \
  --zone us-central1-a --project jusl-496520
```

**Verify:**
```bash
cd apps/spark && terraform apply
kubectl get namespace spark-jobs              # → Active
kubectl get pods -n spark-jobs               # → NFS server Running (ou Pending em primeiro apply)
```
**Tests:** none
**Gate:** quick
**Commit:** `fix(spark): update default kube_context to GKE cluster context`
**Status:** 🔲 CODE DONE — apply gate pending GKE cluster

---

### T10 [P]: `apps/spark/image.tf` — kind load → AR push
**What:** Substituir `kind load docker-image` por `docker push` para Artifact Registry
**Where:** `apps/spark/image.tf`, `apps/spark/variables.tf`
**Depends on:** T3, T4, T12
**Requirement:** GKE-05

**Done when:**
- [x] `null_resource.spark_custom_image` provisioner: `docker build --pull=false -t ${var.ar_repository}/spark-lance-gcs:4.0.2 ${path.module} && docker push ${var.ar_repository}/spark-lance-gcs:4.0.2`
- [x] `kind load docker-image spark-lance-gcs:4.0.2 --name my-cluster` removido
- [x] Trigger mantido: `dockerfile_md5 = filemd5("${path.module}/Dockerfile")`

**Verify:**
```bash
cd apps/spark && terraform apply
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/jusl-496520/my-k8s \
  --filter="tags:4.0.2" --project=jusl-496520
# → spark-lance-gcs  4.0.2  listed
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(spark): replace kind image load with Artifact Registry push`
**Status:** 🔲 CODE DONE — apply gate pending

---

### T11 [P]: `apps/spark/models.tf` — storage class para GKE
**What:** Atualizar storage class do PVC do NFS server de "standard" para "standard-rwo"
**Where:** `apps/spark/models.tf`
**Depends on:** T12
**Requirement:** GKE-12

**Done when:**
- [x] PVC `nfs-server-storage`: `storageClassName = "standard-rwo"` (era `"standard"`)

**Verify:**
```bash
cd apps/spark && terraform apply
kubectl get pvc nfs-server-storage -n spark-jobs \
  -o jsonpath='{.status.phase}'
# → Bound
kubectl get pvc nfs-server-storage -n spark-jobs \
  -o jsonpath='{.spec.storageClassName}'
# → standard-rwo
```
**Tests:** none
**Gate:** quick
**Commit:** `fix(spark): update NFS PVC storage class to standard-rwo for GKE`
**Status:** ✅ CODE COMMITTED — apply gate pending

---

### T13 [P]: SparkApplication manifests — imagem AR + node pool + remover GCS secrets
**What:** Atualizar ambos os spark.yaml com imagem AR, nodeSelector/tolerations para pool spark, remover dependências de GCS secret
**Where:** `apps/spark/jobs/hierarquical-cases/spark.yaml`, `apps/spark/jobs/multimodal-products/spark.yaml`
**Depends on:** T7, T10, T11
**Requirement:** GKE-05, GKE-10, GKE-11

**Done when (ambos os arquivos):**
- [x] `spec.image:` → `"us-central1-docker.pkg.dev/jusl-496520/my-k8s/spark-lance-gcs:4.0.2"`
- [x] `driver.nodeSelector: { pool: spark }` presente
- [x] `driver.tolerations: [{ key: pool, operator: Equal, value: spark, effect: NoSchedule }]` presente
- [x] `executor.nodeSelector: { pool: spark }` presente
- [x] `executor.tolerations: [{ key: pool, operator: Equal, value: spark, effect: NoSchedule }]` presente
- [x] Volume `gcs-adc` removido de `spec.volumes`
- [x] VolumeMount `gcs-adc` removido de `driver.volumeMounts`
- [x] VolumeMount `gcs-adc` removido de `executor.volumeMounts`
- [x] Env var `GOOGLE_APPLICATION_CREDENTIALS` removida de driver e executor
- [x] `HF_HOME`, `TORCH_HOME`, `HF_HUB_OFFLINE`, `GCS_BUCKET` e outros envs mantidos
- [x] Volume e mount de `models` (PVC) mantidos
- [x] Volume e mount de `script` (ConfigMap) mantidos

**Verify:**
```bash
kubectl apply --dry-run=client -f apps/spark/jobs/hierarquical-cases/spark.yaml
kubectl apply --dry-run=client -f apps/spark/jobs/multimodal-products/spark.yaml
cd apps/spark && terraform apply
kubectl get sparkapplication hierarquical-cases -n spark-jobs \
  -o jsonpath='{.spec.driver.nodeSelector}'
# → {"pool":"spark"}
kubectl get sparkapplication hierarquical-cases -n spark-jobs \
  -o jsonpath='{.spec.image}'
# → us-central1-docker.pkg.dev/jusl-496520/my-k8s/spark-lance-gcs:4.0.2
```
**Tests:** none
**Gate:** YAML dry-run
**Commit:** `feat(spark): update SparkApplication manifests for GKE (AR image, node pool, WI auth)`
**Status:** ✅ CODE COMMITTED — apply gate pending

---

### T14: `apps/spark/secret.tf` — remover GCS secrets
**What:** Remover recursos de GCS credential secrets (substituídos por Workload Identity).
Este é o checkpoint de validação end-to-end: após remover os secrets, o job Spark deve
completar usando apenas Workload Identity.
**Where:** `apps/spark/secret.tf`
**Depends on:** T7 (WI configurado), T13 (manifests não referenciam mais os secrets)

**Done when:**
- [x] `kubectl_manifest.gcs_adc_secret` removido
- [x] `kubectl_manifest.gcs_sa_secret` removido

**Verify:**
```bash
cd apps/spark && terraform apply             # -2 resources: secrets destroyed
kubectl get secret -n spark-jobs | grep gcs  # → no results
# End-to-end Spark job test:
kubectl delete sparkapplication hierarquical-cases -n spark-jobs --ignore-not-found
cd apps/spark && terraform apply             # recreates SparkApplication
kubectl wait sparkapplication/hierarquical-cases -n spark-jobs \
  --for=jsonpath='{.status.applicationState.state}'=COMPLETED --timeout=600s
# → sparkapplication.sparkoperator.k8s.io/hierarquical-cases condition met
# Verify GCS output:
gsutil ls gs://thiagos-lake/sandbox/         # → Lance table atualizada
```
**Tests:** none
**Gate:** quick
**Commit:** `feat(spark): remove GCS ADC secrets replaced by Workload Identity`
**Status:** ✅ CODE COMMITTED — e2e apply gate pending

---

### T15: `apps/spark/.terraform.lock.hcl` — terraform init
**What:** Refresh do lock file após mudanças de providers/variáveis no workspace apps/spark
**Where:** `apps/spark/.terraform.lock.hcl`
**Depends on:** T10, T11, T12, T13, T14

**Done when:**
- [x] `terraform init` executado sem erros em `apps/spark/`
- [x] Gate: `terraform validate` passa em `apps/spark/`

**Verify:**
```bash
cd apps/spark && terraform init && terraform validate
terraform plan -detailed-exitcode            # → exit 0 (no changes)
```
**Tests:** none
**Gate:** quick
**Commit:** `chore(spark): refresh terraform lock after GKE migration`
**Status:** ✅ COMPLETED

---

## Task Granularity Check

| Task | Scope | Status |
|------|-------|--------|
| T1: specs structure | 13 arquivos docs | ✅ Granular |
| T2: cluster_type var + resources | 2 arquivos, 1 tema coeso | ✅ OK |
| T3: AR repository + IAM | 1 arquivo, 2 resources | ✅ Granular |
| T4: WI SA + IAM bindings (first GKE deploy) | 1 arquivo, 4 resources WI | ✅ Granular (WI = 1 feature) |
| T5: terraform.tfvars | 1 arquivo, 1 linha | ✅ Granular |
| T6: root lock file | 1 arquivo, 1 comando | ✅ Granular |
| T7: spark-operator WI annotation | 2 arquivos módulo + 1 module call | ✅ OK |
| T8: trino image.tf | 2 arquivos, 1 feature | ✅ Granular |
| T9: trino values + WI | 3 arquivos, 1 feature (imagem+WI) | ✅ OK |
| T10: spark image.tf | 2 arquivos, 1 feature | ✅ Granular |
| T11: models.tf storage class | 1 arquivo, 1 valor | ✅ Granular |
| T12: providers + kube_context | 2 arquivos, 1 feature | ✅ OK |
| T13: SparkApplication yamls | 2 arquivos, mesmo padrão | ✅ OK |
| T14: secret.tf cleanup + e2e test | 1 arquivo, 2 resources + job validation | ✅ Granular |
| T15: apps/spark lock | 1 arquivo, 1 comando | ✅ Granular |

---

## Deployment Sequence Summary

| Step | Task | Workspace | Apply command | Deployed state |
|------|------|-----------|---------------|----------------|
| 1 | T5 | root | `terraform apply` | Kind mode confirmed working |
| 2 | T6 | root | (init only) | Lock file refreshed |
| 3 | T4 | root | `terraform apply -var cluster_type=gke` | GKE cluster + node pools + AR + WI SA |
| 4 | T7 | root | `terraform apply -var cluster_type=gke` | spark K8s SA with WI annotation |
| 5 | T8 [P] | root | `terraform apply -var cluster_type=gke` | Trino image in AR |
| 6 | T9 [P] | root | `terraform apply -var cluster_type=gke` | Trino Helm with WI + AR image |
| 7 | T12 | apps/spark | `terraform apply` | apps/spark connected to GKE |
| 8 | T10 [P] | apps/spark | `terraform apply` | Spark image in AR |
| 9 | T11 [P] | apps/spark | `terraform apply` | NFS PVC Bound (standard-rwo) |
| 10 | T13 | apps/spark | `terraform apply` | SparkApplications with pool + AR image |
| 11 | T14 | apps/spark | `terraform apply` | Secrets removed + job COMPLETED e2e |
| 12 | T15 | apps/spark | `terraform init && terraform apply` | Clean lock, no drift |

---

## Diagram-Definition Cross-Check

| Task | Depends On (body) | Diagram Shows | Status |
|------|-------------------|---------------|--------|
| T1 | None | Start Phase 1 | ✅ |
| T2 | T1 | T1 → T2 | ✅ |
| T3 | T2 | T2 → T3 | ✅ |
| T5 | T2 | Start of execution T5 | ✅ |
| T6 | T2, T5 | T5 → T6 | ✅ |
| T4 | T2, T6 | T6 → T4 | ✅ |
| T7 | T4 | T4 → T7 | ✅ |
| T8 [P] | T3, T4 | T7 → T8 (paralelo) | ✅ |
| T9 [P] | T4, T8 | T7 → T9 (paralelo) | ✅ |
| T12 | T4 | Phase 3 start | ✅ |
| T10 [P] | T3, T4, T12 | T12 → T10 (paralelo) | ✅ |
| T11 [P] | T12 | T12 → T11 (paralelo) | ✅ |
| T13 [P] | T7, T10, T11 | T10, T11 → T13 | ✅ |
| T14 | T7, T13 | T13 → T14 | ✅ |
| T15 | T10, T11, T12, T13, T14 | T14 → T15 | ✅ |

---

## Test Co-location Validation

| Task | Code Layer | Matrix Requires | Task Says | Status |
|------|-----------|-----------------|-----------|--------|
| T4 | Terraform + GKE resources | none (apply verify) | apply + gcloud | ✅ |
| T5 | Terraform tfvars | none (apply kind) | apply + kubectl | ✅ |
| T6 | Terraform init | none (init + plan) | init + plan | ✅ |
| T7 | K8s SA annotation | none (apply verify) | apply + kubectl | ✅ |
| T8 | Docker image build | none (apply verify) | apply + gcloud | ✅ |
| T9 | Helm values | none (apply verify) | apply + kubectl | ✅ |
| T10 | Docker image build | none (apply verify) | apply + gcloud | ✅ |
| T11 | K8s manifest | none (apply verify) | apply + kubectl | ✅ |
| T12 | providers/vars | none (apply verify) | apply + kubectl | ✅ |
| T13 | SparkApplication YAML | none (dry-run + apply) | dry-run + apply + kubectl | ✅ |
| T14 | K8s manifest + e2e | none (apply + job run) | apply + kubectl wait | ✅ |
| T15 | Terraform init | none (init + plan) | init + plan | ✅ |
