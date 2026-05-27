# Feature: Claude Code CLI via GCP Vertex AI in Paperclip Server

## Summary

Replace the `@openai/codex` CLI and OpenAI backend in paperclip with `@anthropic-ai/claude-code` using the `claude_local` adapter, routed through GCP Vertex AI. Authentication uses Workload Identity — no API keys of any kind. `OPENAI_API_KEY` is removed entirely.

## Problem

The paperclip container ships `@openai/codex` and uses `OPENAI_API_KEY` to talk to OpenAI. The project already runs on GKE with Workload Identity and Artifact Registry — Anthropic's Claude models are available on Vertex AI with GCP-native auth, so there is no reason to require any external API key.

## Goals

- Replace OpenAI CLI and backend with Claude Code CLI + `claude_local` adapter
- Zero external API keys — auth flows entirely through Workload Identity
- Minimal IAM blast radius: re-use existing `gke-workloads` GCP SA, following the spark/trino pattern

## Out of Scope

- Creating a new GCP service account (reuse `gke-workloads`)
- Changing the model selection — default Claude Code model applies

---

## Requirements

### R1 — Dockerfile: swap CLI

**File:** `modules/paperclip/Dockerfile`

Replace:
```dockerfile
RUN npm install -g @openai/codex
```
With:
```dockerfile
RUN npm install -g @anthropic-ai/claude-code
```

**Done when:** `docker build` succeeds and `claude --version` runs inside the image.

---

### R2 — Remove OPENAI_API_KEY; add Vertex AI env vars

**File:** `modules/paperclip/main.tf` — `kubernetes_secret.paperclip_env`

Remove `OPENAI_API_KEY` from the secret. Add to the paperclip container at runtime:

| Variable | Value | Purpose |
|---|---|---|
| `ANTHROPIC_VERTEX_PROJECT_ID` | GCP project ID (e.g. `jusl-496520`) | Routes Claude Code CLI to Vertex AI |
| `CLOUD_ML_REGION` | GCP region (e.g. `us-central1`) | Vertex AI region |

No `ANTHROPIC_API_KEY` is set. Vertex AI auth is handled entirely by Workload Identity via the GKE metadata server.

> **Unverified:** Whether the `claude_local` adapter requires an explicit activation env var (e.g. `PAPERCLIP_AI_ADAPTER=claude_local`) could not be confirmed from docs (SPA, private repo). Verify against [Paperclip adapter docs](https://docs.paperclip.ing/#/reference/adapters/claude-local) before implementing. If required, add the var to the secret or as an inline `env {}` block.

**Done when:** `kubectl -n paperclip exec <pod> -- env | grep -E 'ANTHROPIC|CLOUD_ML'` shows both vars and `OPENAI_API_KEY` is absent.

---

### R3 — Kubernetes ServiceAccount with Workload Identity annotation

**File:** `modules/paperclip/main.tf`

Add a `kubernetes_service_account` resource:

```hcl
resource "kubernetes_service_account" "paperclip" {
  metadata {
    name      = "paperclip"
    namespace = kubernetes_namespace.paperclip.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = var.workload_identity_sa_email
    }
  }
}
```

Update the `kubernetes_deployment.paperclip` pod spec to set `service_account_name = "paperclip"`.

**Done when:** Pod runs under the `paperclip` K8s SA and `kubectl describe sa -n paperclip paperclip` shows the annotation.

---

### R4 — IAM: grant Vertex AI access to gke-workloads SA

**File:** `main.tf` (root)

Add (gated on `var.cluster_type == "gke"`):

```hcl
resource "google_project_iam_member" "workloads_vertex_ai" {
  count   = var.cluster_type == "gke" ? 1 : 0
  project = data.google_project.default.id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.gke_workloads[0].email}"
}
```

**Done when:** `gcloud projects get-iam-policy <project> --flatten=bindings --filter=bindings.role=roles/aiplatform.user` shows `gke-workloads` member.

---

### R5 — Workload Identity binding for paperclip

**File:** `main.tf` (root)

Add (gated on `var.cluster_type == "gke"` and `var.paperclip`):

```hcl
resource "google_service_account_iam_member" "paperclip_wi" {
  count              = (var.cluster_type == "gke" && var.paperclip) ? 1 : 0
  service_account_id = google_service_account.gke_workloads[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:jusl-496520.svc.id.goog[paperclip/paperclip]"
  depends_on         = [module.paperclip]
}
```

**Done when:** The GCP SA IAM policy includes the WI principal for `[paperclip/paperclip]`.

---

### R6 — Module variables: remove openai_api_key, add vertex vars

**File:** `modules/paperclip/variables.tf`

Remove `openai_api_key`. Add:

```hcl
variable "vertex_project_id" {
  description = "GCP project ID for Vertex AI (used by Claude Code CLI)"
  type        = string
}

variable "vertex_region" {
  description = "GCP region for Vertex AI"
  type        = string
  default     = "us-central1"
}

variable "workload_identity_sa_email" {
  description = "Email of the GCP SA to annotate the K8s ServiceAccount with"
  type        = string
}
```

**File:** `modules/paperclip/main.tf` — remove `openai_api_key` reference from `kubernetes_secret.paperclip_env`.

**File:** `main.tf` (root) — update `module.paperclip` call (drop `openai_api_key`, add new vars):

```hcl
module "paperclip" {
  count                      = var.paperclip ? 1 : 0
  source                     = "./modules/paperclip"
  ar_repository              = "${var.gcp_region}-docker.pkg.dev/${data.google_project.default.project_id}/my-k8s"
  vertex_project_id          = data.google_project.default.project_id
  vertex_region              = var.gcp_region
  workload_identity_sa_email = try(google_service_account.gke_workloads[0].email, "")
}
```

**File:** `variables.tf` (root) — remove `paperclip_openai_api_key` variable.

**Done when:** `terraform plan` shows no unknown inputs, no references to `openai_api_key` remain in the module.

---

## Affected Files

| File | Change |
|---|---|
| `modules/paperclip/Dockerfile` | R1: swap `@openai/codex` → `@anthropic-ai/claude-code` |
| `modules/paperclip/main.tf` | R2: remove `OPENAI_API_KEY`, add Vertex AI vars; R3: add K8s SA + update deployment |
| `modules/paperclip/variables.tf` | R6: remove `openai_api_key`; add `vertex_project_id`, `vertex_region`, `workload_identity_sa_email` |
| `variables.tf` | R6: remove `paperclip_openai_api_key` |
| `main.tf` | R4: add IAM member; R5: add WI binding; R6: update module call (drop `openai_api_key`) |

---

## Verification

```bash
# 1. terraform plan — no errors, shows IAM/WI additions, no openai_api_key references
terraform plan

# 2. After apply — confirm Claude Code CLI is present
kubectl -n paperclip exec deploy/paperclip -- claude --version

# 3. Confirm Vertex AI env vars are set and OPENAI_API_KEY is gone
kubectl -n paperclip exec deploy/paperclip -- env | grep -E 'ANTHROPIC|CLOUD_ML|OPENAI'

# 4. Smoke test — Claude Code routes via Vertex AI (no API key error)
kubectl -n paperclip exec deploy/paperclip -- claude -p "say hello"

# 5. IAM verification
gcloud projects get-iam-policy jusl-496520 \
  --flatten="bindings[].members" \
  --filter="bindings.role=roles/aiplatform.user"
```
