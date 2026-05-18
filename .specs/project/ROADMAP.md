# Roadmap

## M1 — Migração Kind → GKE com dual-mode (cluster_type var)
**Status:** Em Planejamento
**Feature:** gke-migration
**Entregáveis:**
- GKE cluster us-central1-a + autoscaling node pools (system min=1, spark min=0)
- `cluster_type` variable para alternar Kind ↔ GKE
- Artifact Registry para imagens Docker (substitui kind load)
- Workload Identity (GCP SA gke-workloads, bindings para spark-jobs/spark e trino/trino)
- SparkApplication manifests com nodeSelector/tolerations para pool spark
- NFS PVC com storage class correta (standard-rwo no GKE)

## M2 — Spark jobs estáveis no GKE (scale-to-zero validado)
**Status:** Bloqueado por M1
**Entregáveis:**
- hierarquical-cases job completando com sucesso no GKE
- Pool spark escalando de 0 → N → 0 por ciclo de job
- multimodal-products job reabilitado (remover de excluded_jobs)

## M3 — Trino no GKE com WI e Lance connector validado
**Status:** Bloqueado por M1
**Entregáveis:**
- Trino usando Workload Identity para GCS (sem ADC JSON)
- Lance connector Trino consultando tabelas em bronze/sandbox via GKE
- Playground Python consultando Trino no GKE

## M4 — Observabilidade e gestão de custos
**Status:** Deferred
**Entregáveis:**
- Alertas de custo GKE
- Logging estruturado de Spark jobs
- Limpeza automática de SparkApplications expirados
