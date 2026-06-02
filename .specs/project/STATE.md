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
| cases-pdf-processor cold start | Custom Docker image com modelos Docling pré-baked | Evita download de ~500MB de modelos a cada cold start (~2-3min → ~10s) | 2026-05-21 |
| cases-pdf-processor deployment | Cloud Run v2 (ambas as funções) | Suporta imagem Docker pré-construída; mesmo padrão do null_resource de spark/image.tf | 2026-05-21 |
| cases-pdf-processor AR repos | Repositório AR dedicado por função (cases-pdf-indexer, cases-pdf-converter) | Isolamento de imagens por função | 2026-05-21 |

## Active Work

- Feature `lakehouse-mcp`: T1–T5 ✅ implemented (2026-06-01), T6 smoke test pending (needs `terraform apply`)
  - `apps/lakehouse-mcp/` — server.py (FastMCP SSE port 8000, query_vector/fts/sql), pyproject.toml, Dockerfile, image.tf, providers.tf, variables.tf, terraform.tfvars, k8s.tf
  - `.claude/skills/lakehouse-query/SKILL.md` + `.skill-meta.json`
  - T6 smoke test: `cd apps/lakehouse-mcp && terraform apply`, then verify per tasks.md checklist

- Feature `gke-migration`: spec/design/tasks criados, implementação pendente
- Feature `cases-pdf-processor`: ✅ implementação completa (T1–T10), pronto para `terraform apply`
- Feature `spark-etl-framework`: ✅ implementação completa (T1–T9), 34/34 testes passando
- Feature `adapt-jobs-to-spark-etl`: ✅ implementação completa (T1–T5), 41/41 testes passando
- Feature `cases-summarizer`: ✅ implementação completa (T1–T8), pronto para `terraform apply`
  - `modules/keda/` — Helm module para instalar KEDA (chart_version=2.16.0)
  - `modules/cases-summarizer/` — GCP SA, IAM GCS (prefix conditions), pull subscription com DLQ
  - `apps/cases-summarizer/worker.py` — pull loop, pypdf extraction, OpenAI classification, embeddings all-MiniLM-L6-v2, Lance write
  - `apps/cases-summarizer/` — Dockerfile (python:3.13-slim, uv, model pre-bake), pyproject.toml, image.tf, k8s.tf, keda.tf
  - Root: `var.keda`, `var.cases_summarizer`, `var.openai_api_key` adicionados; módulos wired atrás de feature flags
- Feature `refactor-hierarquical-cases-to-markdown`: ✅ implementação completa
  - Novo conector `GCSMarkdownSource` lê `.md` de `gs://{bucket}/{prefix}` (output do cases-pdf-processor)
  - `chunk_markdown` substitui `transform_legal_cases` — chunking heading-based + embeddings all-MiniLM-L6-v2
  - Tabela Lance renomeada `hierarquical_cases` → `cases_chunks`; coluna `embedding_model` adicionada ao schema
  - `GCS_PDF_PATH` / `DOCLING_CACHE_DIR` removidos de spark.yaml; `GCS_MD_PREFIX` adicionado
  - `docling` removido do Dockerfile

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
