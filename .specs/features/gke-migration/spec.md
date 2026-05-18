# GKE Migration Specification

## Problem Statement

O cluster Kind local não consegue processar os Spark ML jobs com CLIP + sentence-transformers + Docling em paralelo (driver 4GB + 2 executors 3GB cada = 10GB mínimo, mais OS/JVM overhead). Kind sofre OOM ou timeout. A migração para GKE provê compute real e elástico via autoscaling, mantendo a capacidade de alternar para Kind localmente via variável Terraform.

## Goals

- [ ] Cluster GKE provisionado via `terraform apply -var cluster_type=gke`
- [ ] Spark jobs executando com scale-to-zero no pool `spark`
- [ ] Imagens Docker em Artifact Registry (sem `kind load`)
- [ ] GCS auth via Workload Identity (sem JSON keys)
- [ ] Kind cluster continua funcionando com `cluster_type = "kind"` (default)

## Out of Scope

| Feature | Reason |
|---------|--------|
| GPU node pool | Fora do budget atual |
| Multi-zona (regional) | Desnecessário para uso pessoal |
| CI/CD automatizado de builds | Próximo milestone |
| Trino Lance connector WI validation | Risco técnico — validar em execução |
| Renomear "hierarquical" → "hierarchical" | Refactor cosmético, não blocker |
| Reabilitar multimodal-products job | Dependente da migração ser estável |

---

## User Stories

### P1: cluster_type variable para dual-mode ⭐ MVP
**User Story:** Como operator de infra, quero uma variável `cluster_type` que alterna entre Kind e GKE sem destruir a infra existente, para que eu possa testar localmente e escalar quando necessário.

**Why P1:** Sem isso, a migração seria destrutiva — perderia o cluster Kind que funciona hoje.

**Acceptance Criteria:**
1. WHEN `cluster_type = "kind"` THEN terraform SHALL provisionar `kind_cluster.my-cluster` com 1 CP + 2 workers
2. WHEN `cluster_type = "gke"` THEN terraform SHALL provisionar `google_container_cluster.my_cluster` em us-central1-a
3. WHEN `cluster_type` tem valor inválido THEN terraform validate SHALL retornar erro de validation
4. WHEN `cluster_type = "kind"` THEN providers kubernetes e helm SHALL usar kubeconfig/context
5. WHEN `cluster_type = "gke"` THEN providers kubernetes e helm SHALL usar endpoint/token GKE

**Independent Test:** `terraform validate` passa para ambos os valores sem apply no cluster.

**Requirement IDs:** GKE-04

---

### P1: GKE cluster com autoscaling node pools ⭐ MVP
**User Story:** Como operator de infra, quero um cluster GKE com node pool `system` (sempre ativo) e `spark` (scale-to-zero), para que Spark jobs tenham compute real e não desperdicem recursos quando ociosos.

**Why P1:** Core da migração — sem o cluster GKE, nada mais funciona.

**Acceptance Criteria:**
1. WHEN `cluster_type = "gke"` THEN terraform SHALL criar `google_container_cluster` com Workload Identity habilitado
2. WHEN `cluster_type = "gke"` THEN pool `system` SHALL ter min_node_count=1, max_node_count=3, e2-standard-4
3. WHEN `cluster_type = "gke"` THEN pool `spark` SHALL ter min_node_count=0, max_node_count=10, label pool=spark, taint pool=spark:NoSchedule
4. WHEN nenhum SparkApplication está ativo THEN autoscaler SHALL escalar pool `spark` para 0 nós
5. WHEN SparkApplication é criado com nodeSelector/toleration THEN autoscaler SHALL provisionar nó no pool `spark`

**Independent Test:** `kubectl get nodes` mostra nós system e, após job, nós spark.

**Requirement IDs:** GKE-01, GKE-02, GKE-03

---

### P1: Docker images em Artifact Registry ⭐ MVP
**User Story:** Como operator de infra, quero que as imagens Docker sejam pushed para o Artifact Registry ao invés de `kind load`, para que os nós GKE possam fazer pull.

**Why P1:** Sem imagens acessíveis no GKE, os pods ficam em ErrImagePull.

**Acceptance Criteria:**
1. WHEN Dockerfile muda THEN terraform null_resource SHALL fazer `docker push` para `us-central1-docker.pkg.dev/my-k8s-495416/my-k8s/`
2. WHEN nós GKE iniciam THEN eles SHALL ter permissão `artifactregistry.reader`
3. WHEN SparkApplication é criado THEN spec.image SHALL referenciar a URL completa do AR

**Independent Test:** `gcloud artifacts docker images list` mostra as duas imagens.

**Requirement IDs:** GKE-05, GKE-06

---

### P1: Workload Identity para GCS ⭐ MVP
**User Story:** Como operator de infra, quero que pods Spark e Trino se autentiquem no GCS via Workload Identity, para que não seja necessário gerenciar JSON keys ou arquivos ADC locais.

**Why P1:** Sem auth GCS funcionando, todos os Spark jobs falham (lêem e escrevem em GCS).

**Acceptance Criteria:**
1. WHEN `cluster_type = "gke"` THEN terraform SHALL criar GCP SA `gke-workloads` com `roles/storage.objectAdmin`
2. WHEN `cluster_type = "gke"` THEN terraform SHALL criar WI binding para `spark-jobs/spark`
3. WHEN `cluster_type = "gke"` THEN terraform SHALL criar WI binding para `trino/trino`
4. WHEN K8s SA `spark` é criada THEN ela SHALL ter annotation `iam.gke.googleapis.com/gcp-service-account`
5. WHEN Spark job roda no GKE THEN env var `GOOGLE_APPLICATION_CREDENTIALS` NOT SHALL estar presente
6. WHEN Spark job roda no GKE THEN `storage.Client()` SHALL autenticar via ADC sem arquivos locais

**Independent Test:** Spark job completa sem erros de permission no GCS.

**Requirement IDs:** GKE-07, GKE-08, GKE-09

---

### P2: Spark pods no node pool correto
**User Story:** Como operator de infra, quero que driver e executor pods Spark sejam agendados no pool `spark` (com taint), para que workloads do sistema não sejam interrompidos durante scale-up/down.

**Why P2:** Importante para estabilidade mas não bloqueia o funcionamento básico (pods iriam para system pool sem isso).

**Acceptance Criteria:**
1. WHEN SparkApplication é criado THEN driver.nodeSelector SHALL ter `pool: spark`
2. WHEN SparkApplication é criado THEN driver.tolerations SHALL ter `key: pool, value: spark, effect: NoSchedule`
3. WHEN SparkApplication é criado THEN executor.nodeSelector SHALL ter `pool: spark`
4. WHEN SparkApplication é criado THEN executor.tolerations SHALL ter `key: pool, value: spark, effect: NoSchedule`

**Independent Test:** `kubectl apply --dry-run=client` passa; após job, `kubectl get pods -n spark-jobs -o wide` mostra driver/executor em nó do pool spark.

**Requirement IDs:** GKE-10, GKE-11

---

### P2: NFS model cache funcional no GKE
**User Story:** Como Spark job, quero que o PVC do NFS server faça bind corretamente no GKE, para que os modelos de embedding estejam disponíveis nos pods sem download repetido.

**Why P2:** Sem o NFS cache, os jobs baixariam modelos a cada execução (>1GB, HF_HUB_OFFLINE=1 falharia).

**Acceptance Criteria:**
1. WHEN apps/spark terraform apply no GKE THEN PVC `nfs-server-storage` SHALL usar `storageClassName: standard-rwo`
2. WHEN NFS server pod inicia THEN PVC `nfs-server-storage` SHALL estar em estado `Bound`
3. WHEN Spark pods montam `spark-models-pvc` THEN NFS PVC SHALL estar acessível em ReadWriteMany

**Independent Test:** `kubectl get pvc -n spark-jobs` mostra ambos os PVCs em Bound.

**Requirement IDs:** GKE-12

---

## Edge Cases

- WHEN `cluster_type` muda de "gke" para "kind" THEN terraform SHALL destruir recursos GKE e criar Kind (usuário deve estar ciente)
- WHEN apps/spark apply roda antes de `gcloud get-credentials` THEN kubectl provider SHALL falhar com erro de conexão (comportamento esperado — documentado no workflow)
- WHEN spark pool está em 0 nós e SparkApplication é submetido THEN driver pod SHALL ficar em Pending até autoscaler provisionar nó (~2 min)
- WHEN `workload_identity_sa_email` está vazio (cluster_type=kind) THEN spark SA SHALL ser criada sem annotation WI (sem erro)

---

## Requirement Traceability

| Requirement ID | Story | Status |
|---------------|-------|--------|
| GKE-01 | P1: GKE cluster | Pending |
| GKE-02 | P1: system node pool | Pending |
| GKE-03 | P1: spark node pool autoscaling | Pending |
| GKE-04 | P1: cluster_type variable | Pending |
| GKE-05 | P1: AR repository + image push | Pending |
| GKE-06 | P1: AR IAM pull para node SA | Pending |
| GKE-07 | P1: GCP SA gke-workloads | Pending |
| GKE-08 | P1: WI binding spark-jobs/spark | Pending |
| GKE-09 | P1: WI binding trino/trino | Pending |
| GKE-10 | P2: SparkApplication nodeSelector | Pending |
| GKE-11 | P2: SparkApplication tolerations | Pending |
| GKE-12 | P2: NFS PVC storage class | Pending |

## Success Criteria

- [ ] `terraform apply -var cluster_type=gke` completa sem erros
- [ ] `kubectl get nodes` mostra ≥1 nó no pool system, 0 no pool spark
- [ ] SparkApplication `hierarquical-cases` completa com status `COMPLETED` no GKE
- [ ] Pool spark escala de 0 → N durante job e volta a 0 após TTL
- [ ] `gsutil ls gs://thiagos-lake/sandbox/` mostra tabela Lance atualizada
- [ ] `terraform apply -var cluster_type=kind` continua funcionando após a migração
