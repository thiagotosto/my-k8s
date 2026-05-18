# Tech Stack

**Analyzed:** 2026-05-18

## Core Infrastructure

- IaC: Terraform >= 1.3.0 (dois workspaces: root e apps/spark)
- Cluster local: Kind 0.17.0 (provider justenwalker/kind)
- Cluster target: GKE (google provider 6.50.0)
- State Backend: GCS (juslake-terraform-state para root, thiago-terraform-state para apps/spark)

## Kubernetes Operators / Helm

- Spark Operator: Kubeflow spark-operator 2.1.0 (Helm, kubeflow.github.io/spark-operator)
- Query Engine: Trino 476 (Helm, trinodb/charts 0.27.0)

## Compute

- Spark: Apache Spark 4.0.2 (PySpark, cluster mode)
- Custom Spark image: spark-lance-gcs:4.0.2
- Custom Trino image: trino-lance-gcs:476-v0.2.2

## Storage

- Lance on GCS: bronze catalog (gs://thiagos-lake/bronze) + sandbox (gs://thiagos-lake/sandbox)
- NFS in-cluster: pod itsthenetwork/nfs-server-alpine com PVC 5Gi (model cache ReadWriteMany)
- GCS Buckets: thiagos-lake (dados), juslake (PDFs), juslake-terraform-state, thiago-terraform-state

## ML Libraries (Spark image)

- lance-spark-bundle 4.0_2.13-0.4.0 (JAR)
- gcs-connector hadoop3-2.2.22 (JAR shaded)
- PyTorch CPU, torchvision
- sentence-transformers (all-MiniLM-L6-v2, 384d)
- open-clip-torch (ViT-B-32 CLIP, 512d)
- lancedb, pylance, pandas, google-cloud-storage, pypdf, docling

## Terraform Providers

- hashicorp/google 6.50.0 (`~> 6.0`)
- hashicorp/kubernetes 3.1.0
- hashicorp/helm 3.1.1
- hashicorp/null 3.2.4 (`~> 3.0`)
- justenwalker/kind 0.17.0
- gavinbunney/kubectl ~1.14 (apps/spark workspace)

## Auth

- Local (Kind): ADC de ~/.config/gcloud/application_default_credentials.json (montado como Kubernetes Secret)
- Target (GKE): Workload Identity — GCP SA gke-workloads vinculado aos K8s SAs spark e trino

## Testing

Nenhum framework de testes automatizados — validação manual via terraform validate, kubectl e gsutil.
