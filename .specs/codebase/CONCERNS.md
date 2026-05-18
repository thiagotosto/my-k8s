# Concerns

## HIGH — kind load docker-image não funciona no GKE

**Evidence:** `apps/spark/image.tf` linha 5: `kind load docker-image spark-lance-gcs:4.0.2 --name my-cluster` e `modules/trino/image.tf`: `kind load docker-image trino-lance-gcs:476-v0.2.2 --name my-cluster`
**Impact:** Imagens não serão carregadas em nós GKE — pods ficarão em `ErrImagePull`
**Fix:** Migrar para Artifact Registry push (tasks T8 e T10)

---

## HIGH — GCS auth via JSON file local quebra no GKE

**Evidence:** `apps/spark/secret.tf` lê `~/.config/gcloud/application_default_credentials.json` em tempo de `terraform apply`. No GKE, o arquivo pode não existir ou estar desatualizado.
**Impact:** `terraform apply` falha ao criar o secret `gcs-adc` no workspace apps/spark
**Fix:** Workload Identity elimina a dependência do arquivo (task T14 remove secret.tf)

---

## HIGH — storageClassName "standard" não existe no GKE

**Evidence:** `apps/spark/models.tf` — PVC `nfs-server-storage`: `storageClassName = "standard"`
**Impact:** PVC fica em estado `Pending` indefinidamente no GKE (storage class inexistente)
**Fix:** Mudar para `standard-rwo` (GCE Persistent Disk, task T11)

---

## HIGH — kube_context hardcoded para Kind

**Evidence:** `apps/spark/variables.tf`: `default = "kind-my-cluster"` para `kube_context`
**Impact:** apps/spark workspace falha ao conectar no GKE sem override manual de `-var kube_context=...`
**Fix:** Atualizar default para `gke_my-k8s-495416_us-central1-a_my-cluster` (task T12)

---

## MEDIUM — SparkApplication image sem registry prefix

**Evidence:** `apps/spark/jobs/hierarquical-cases/spark.yaml`: `image: "spark-lance-gcs:4.0.2"` (sem registry)
**Impact:** No GKE, sem prefix de registry, o pull tentará DockerHub e falhará
**Fix:** Atualizar para `us-central1-docker.pkg.dev/my-k8s-495416/my-k8s/spark-lance-gcs:4.0.2` (task T13)

---

## MEDIUM — Two-pass terraform apply após criar GKE cluster

**Evidence:** apps/spark usa kubeconfig (não terraform state do root) para conectar ao cluster
**Impact:** Após `terraform apply` no root com `cluster_type=gke`, usuário deve executar `gcloud container clusters get-credentials` antes de aplicar apps/spark
**Mitigation:** Documentado no design doc (não é bug, é limitação arquitetural dos dois workspaces)

---

## MEDIUM — GCS SA key em disco para multimodal-products

**Evidence:** `apps/spark/secret.tf` lê `jobs/multimodal-products/credentials/my-k8s-495416-f42aa843ffe3.json`
**Impact:** Arquivo sensível em disco; com WI, não é necessário
**Fix:** Removido com WI (task T14); o job está em `excluded_jobs` no momento

---

## LOW — Typo no nome do job

**Evidence:** `apps/spark/jobs/hierarquical-cases/` — "hierarquical" deveria ser "hierarchical"
**Impact:** Cosmético — o job funciona, mas o nome é incorreto em inglês
**Fix:** Renomear em refactor futuro (fora do scope desta migração)

---

## LOW — imagePullPolicy: IfNotPresent pode cachear imagem antiga no GKE

**Evidence:** `spark.yaml` de ambos os jobs usa `imagePullPolicy: IfNotPresent`
**Impact:** Se o nó já tiver uma versão anterior da imagem, não fará pull da nova
**Fix:** Usar digest-based tags ou `Always` — deferir para após migração inicial estável
