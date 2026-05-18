# my-k8s

**Vision:** Plataforma de ML/Data Lake pessoal rodando em Kubernetes, com Spark jobs de embeddings multimodais, Trino para query analítica e Lance tables em GCS como camada de armazenamento vetorial.
**For:** Desenvolvedor individual explorando ML e data engineering
**Solves:** Falta de ambiente local escalável para processar Spark ML jobs pesados (CLIP, sentence-transformers, Docling) — o cluster Kind não tem CPU/RAM suficientes

## Goals

- Processar Spark ML jobs sem limitação de CPU/RAM do Kind
- Infraestrutura reproducível via Terraform que alterna entre Kind (dev local) e GKE (compute real) via `cluster_type` variable
- GCS como camada de armazenamento permanente para Lance tables (bronze/sandbox)
- Zero credenciais JSON em disco — Workload Identity no GKE

## Tech Stack

**Core:**
- IaC: Terraform >= 1.3.0 (dois workspaces: root + apps/spark)
- Cluster: Kind (local) / GKE us-central1-a (target)
- State Backend: GCS (juslake-terraform-state / thiago-terraform-state)

**Compute:**
- Spark: Apache Spark 4.0.2 via Kubeflow spark-operator 2.1.0
- Custom image: spark-lance-gcs:4.0.2 (base apache/spark:4.0.2 + Lance + GCS + ML libs)

**Query:**
- Trino 476 via Helm (trinodb/charts 0.27.0)
- Custom image: trino-lance-gcs:476-v0.2.2 (Lance connector)

**Storage:**
- Lance on GCS (bronze → thiagos-lake/bronze, sandbox → thiagos-lake/sandbox)
- NFS in-cluster para model cache (ReadWriteMany)

**Key Dependencies (Spark image):**
- lance-spark-bundle 4.0_2.13-0.4.0, gcs-connector hadoop3-2.2.22
- PyTorch CPU, sentence-transformers, open-clip-torch, lancedb, docling

## Scope

**v1 inclui:**
- GKE cluster com autoscaling node pools (system min=1, spark min=0)
- Artifact Registry para imagens Docker
- Workload Identity (GCP SA + K8s SA bindings)
- `cluster_type` variable alternando Kind ↔ GKE sem destruir infra

**Explicitamente fora de escopo:**
- GPU node pool
- Multi-zona ou alta disponibilidade
- CI/CD automatizado para builds de imagem
- Pipeline de ingestão contínua

## Constraints

- Budget: instâncias e2-standard-4 (custo mínimo)
- GCP Project: my-k8s-495416
- Região: us-central1-a (zonal)
