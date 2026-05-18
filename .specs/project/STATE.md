# State

## Decisions

| Decision | Choice | Why | Date |
|----------|--------|-----|------|
| Cluster target | GKE us-central1-a (zonal) | Menor complexidade que regional, suficiente para uso pessoal | 2026-05-18 |
| Auth GCS workloads | Workload Identity | Sem JSON keys em disco, padrão GKE | 2026-05-18 |
| Model cache | NFS in-cluster (GCE PD backend) | Sem custo adicional vs Filestore (min 1TB ~$200/mês) | 2026-05-18 |
| Node pools | system (min=1) + spark (min=0) | spark pool em scale-to-zero economiza custo quando sem jobs | 2026-05-18 |
| Node machine type | e2-standard-4 (4vCPU, 16GB) | Cabe driver(4GB) + executor(3GB) × 2 + overhead | 2026-05-18 |
| Imagens Docker | Artifact Registry us-central1 | Substitui `kind load docker-image` que não funciona no GKE | 2026-05-18 |
| cluster_type var | default "kind" | Não quebra estado atual do Kind ao fazer apply sem flag | 2026-05-18 |
| AR registry name | "my-k8s" | Consistente com nome do projeto | 2026-05-18 |

## Active Work

- Feature `gke-migration`: spec/design/tasks criados, implementação pendente (próxima sessão)
- Spec files: criados em `.specs/` (esta sessão)

## Blockers

Nenhum no momento.

## Lessons Learned

- Kind não aguenta Spark ML jobs com CLIP + sentence-transformers simultaneamente em dois executors (3GB cada) + driver (4GB) — OOM ou timeout
- `kind load docker-image` é incompatível com GKE — necessita Artifact Registry ou GCR
- Dois Terraform workspaces independentes (root + apps/spark) requerem sequência de apply explícita após criar cluster GKE

## Deferred Ideas

- GPU node pool (n1-standard-4 + T4) para modelos maiores
- Multi-zona para HA
- Digest-based Docker tags para evitar cache de imagens antigas no GKE
- Renomear "hierarquical-cases" → "hierarchical-cases" (typo)
- Reabilitar multimodal-products job (atualmente em excluded_jobs)

## Preferences

- Respostas concisas, sem Co-Authored-By nos commits
