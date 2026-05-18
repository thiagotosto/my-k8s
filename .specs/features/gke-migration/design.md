# GKE Migration Design

## Architecture Overview

```
Root Terraform Workspace
├── variable "cluster_type" ["kind"|"gke"] default="kind"
│
├── kind_cluster.my-cluster          (count = cluster_type == "kind" ? 1 : 0)
│     1 control-plane + 2 workers
│
├── google_container_cluster.my_cluster (count = cluster_type == "gke" ? 1 : 0)
│     location: us-central1-a
│     workload_identity_config.workload_pool = "my-k8s-495416.svc.id.goog"
│     deletion_protection: false
│
├── google_container_node_pool.system (count = cluster_type == "gke" ? 1 : 0)
│     autoscaling: min=1, max=3 / machine: e2-standard-4
│     workload_metadata_config: GKE_METADATA
│     workloads: spark-operator, Trino, NFS server
│
├── google_container_node_pool.spark  (count = cluster_type == "gke" ? 1 : 0)
│     autoscaling: min=0, max=10 / machine: e2-standard-4
│     label: pool=spark / taint: pool=spark:NoSchedule
│     workload_metadata_config: GKE_METADATA
│     workloads: Spark driver + executors
│
├── google_artifact_registry_repository.my_k8s (count = cluster_type == "gke" ? 1 : 0)
│     location: us-central1, format: DOCKER, id: my-k8s
│
├── google_service_account.gke_workloads (count = cluster_type == "gke" ? 1 : 0)
│     roles/storage.objectAdmin → GCS buckets
│     WI binding: spark-jobs/spark
│     WI binding: trino/trino
│
├── provider "kubernetes"  ← auth condicional: GKE token OU kubeconfig Kind
├── provider "helm"        ← auth condicional: GKE token OU kubeconfig Kind
│
├── module spark-operator
│     workload_identity_sa_email = try(gke_workloads[0].email, "")
│     → K8s SA spark + WI annotation (quando gke)
│
└── module trino
      workload_identity_sa_email = try(gke_workloads[0].email, "")
      → AR image + WI SA annotation (quando gke)

apps/spark Workspace (Terraform state separado)
├── null_resource.spark_custom_image → docker build + push AR (ou kind load)
├── NFS server pod/svc/pvc (storageClass: standard-rwo no GKE)
└── SparkApplications ← nodeSelector + toleration para pool spark
```

## Provider Auth Strategy

```hcl
data "google_client_config" "default" {}

locals {
  gke_endpoint = try(google_container_cluster.my_cluster[0].endpoint, "")
  gke_ca_cert  = var.cluster_type == "gke" ? try(
    base64decode(google_container_cluster.my_cluster[0].master_auth[0].cluster_ca_certificate),
    null
  ) : null
}

provider "kubernetes" {
  # GKE mode: autenticação via token do cluster
  host                   = var.cluster_type == "gke" ? "https://${local.gke_endpoint}" : null
  token                  = var.cluster_type == "gke" ? data.google_client_config.default.access_token : null
  cluster_ca_certificate = local.gke_ca_cert
  # Kind mode: autenticação via kubeconfig local
  config_path    = var.cluster_type == "kind" ? var.kubeconfig_path : null
  config_context = var.cluster_type == "kind" ? var.kube_context : null
}
# provider "helm" usa a mesma estrutura
```

**Por que try():** `google_container_cluster.my_cluster[0].endpoint` é unknown durante plan se count=0. `try()` resolve para string vazia sem erro de plan.

## Workload Identity Flow

```
GCP SA: gke-workloads@my-k8s-495416.iam.gserviceaccount.com
  └── roles/storage.objectAdmin (leitura e escrita em GCS)

WI Bindings (google_service_account_iam_member):
  member: serviceAccount:my-k8s-495416.svc.id.goog[spark-jobs/spark]
  member: serviceAccount:my-k8s-495416.svc.id.goog[trino/trino]

K8s SA annotation (adicionada pelo módulo spark-operator e Helm values do Trino):
  iam.gke.googleapis.com/gcp-service-account: gke-workloads@my-k8s-495416.iam.gserviceaccount.com

Runtime (Spark/Trino pod):
  → Node pool configurado com GKE_METADATA mode
  → Pod troca token K8s SA por access token do GCP SA via metadata server 169.254.169.254
  → Application Default Credentials detecta automaticamente (sem GOOGLE_APPLICATION_CREDENTIALS)
  → GCS Hadoop connector e google-cloud-storage Python usam ADC normalmente
```

**Consequência para SparkApplications:** Remover volume `gcs-adc`, volumeMounts e env `GOOGLE_APPLICATION_CREDENTIALS` — esses campos eram necessários apenas com JSON key file.

**Configuração Spark mantida (independente de auth):**
```yaml
sparkConf:
  spark.hadoop.google.cloud.auth.type: APPLICATION_DEFAULT
```
Essa config instrui o GCS connector a usar ADC — funciona tanto com arquivo JSON (Kind) quanto com WI (GKE).

## Artifact Registry Image Flow

```
Antes (Kind):
  docker build -t spark-lance-gcs:4.0.2 ./apps/spark
  kind load docker-image spark-lance-gcs:4.0.2 --name my-cluster

Depois (GKE):
  docker build -t us-central1-docker.pkg.dev/my-k8s-495416/my-k8s/spark-lance-gcs:4.0.2 ./apps/spark
  docker push us-central1-docker.pkg.dev/my-k8s-495416/my-k8s/spark-lance-gcs:4.0.2

SparkApplication.spec.image (spark.yaml):
  "us-central1-docker.pkg.dev/my-k8s-495416/my-k8s/spark-lance-gcs:4.0.2"

Trino Helm values:
  image.repository: us-central1-docker.pkg.dev/my-k8s-495416/my-k8s/trino-lance-gcs

Node SA para pull: {project_number}-compute@developer.gserviceaccount.com
  → roles/artifactregistry.reader
```

## Scale-to-Zero Spark Pool

```
Estado inicial (sem jobs):
  pool spark: 0 nós

SparkApplication submetida:
  1. driver pod criado com nodeSelector: {pool: spark} + toleration pool=spark:NoSchedule
  2. Pod fica em Pending (nenhum nó disponível no pool spark)
  3. GKE Cluster Autoscaler detecta pod Pending com nodeSelector → provisiona nó (~2 min)
  4. Driver pod agenda no novo nó, inicia, cria executor pods (mesmos nodeSelector/toleration)
  5. Job processa → GCS output
  6. Job completa → TTL 300s → pods removidos
  7. Pool spark fica sem pods elegíveis → autoscaler escala para 0 nós (~10 min)

Pool system: sempre min=1 nó
  → spark-operator controller disponível para receber novas SparkApplications
  → Trino ativo para queries durante e entre jobs
  → NFS server disponível (modelo cache persistente)
```

**Requirement para scale-to-zero funcionar:**
- Pod deve ter `nodeSelector` + `toleration` que apontam especificamente para o pool spark
- Pods sem esses campos iriam para o pool system (sem taint) — o autoscaler não escalaria o pool spark

## apps/spark Workspace Integration

```
Root workspace e apps/spark NÃO compartilham estado Terraform.
apps/spark conecta ao cluster via kubeconfig.

Workflow pós-migração GKE:
  1. terraform apply -var cluster_type=gke        (root — cria GKE cluster)
  2. gcloud container clusters get-credentials my-cluster \
       --zone us-central1-a --project my-k8s-495416  (atualiza kubeconfig)
  3. terraform apply \
       -var kube_context=gke_my-k8s-495416_us-central1-a_my-cluster \
       (apps/spark — deploy workloads)

Alternativa: definir no apps/spark/terraform.tfvars:
  kube_context = "gke_my-k8s-495416_us-central1-a_my-cluster"
```

## NFS Model Cache no GKE

```
NFS server pod (pool system):
  PVC nfs-server-storage: 5Gi, storageClassName: standard-rwo (GCE PD zonal)
  Container: itsthenetwork/nfs-server-alpine (privileged, porta 2049)
  Export: /exports

Client PVC (ReadWriteMany — NFS backed):
  spark-models-pvc → PersistentVolume → NFS server ClusterIP:2049

Spark pods:
  volumeMount: spark-models-pvc → /opt/spark/models
  HF_HOME=/opt/spark/models
  HF_HUB_OFFLINE=1 (modelos já baixados no cache)
```

**Nota:** GCE PD é zonal. Com cluster zonal (us-central1-a), o NFS server sempre agenda na mesma zona que o PD — sem problemas. Se migrar para cluster regional, adicionar nodeAffinity no NFS server pod.

## Variables Impact Summary

| Variable | Workspace | Kind mode | GKE mode |
|----------|-----------|-----------|----------|
| `cluster_type` | root | "kind" (default) | "gke" |
| `kubeconfig_path` | root + apps/spark | ~/.kube/config | não usado (root) |
| `kube_context` | root + apps/spark | kind-my-cluster | gke_... (apps/spark) |
| `gcp_region` | root | us-central1 | us-central1 |
| `gcp_zone` | root | us-central1-a | us-central1-a |
| `ar_repository` | apps/spark | não usado | us-central1-docker.pkg.dev/... |
| `workload_identity_sa_email` | modules | "" (vazio) | gke-workloads@... |
