# Tasks: Claude Code CLI via GCP Vertex AI in Paperclip Server

## Dependency Graph

```
T1 (Dockerfile)      ──────────────────────────────────────────► done
T2 (module vars)     ──────────────► T3 (module main.tf) ──────► done
T4 (root vars)       ──────────────────────────────────────────► done
                                     T5 (root main.tf)   ──────► done
                     (T2 + T3 done before T5 to ensure module
                      vars exist when root references them)
```

**Wave 1 [P]:** T1, T2, T4 — fully independent, different files
**Wave 2 [P]:** T3, T5 — both depend on T2; touch different files (module vs root)

---

## T1 — Dockerfile: swap CLI

**Implements:** R1
**File:** `modules/paperclip/Dockerfile`
**Depends on:** —
**Parallel:** [P] with T2, T4

**What:** Replace `npm install -g @openai/codex` with `npm install -g @anthropic-ai/claude-code`.

**Done when:**
- `modules/paperclip/Dockerfile` contains `@anthropic-ai/claude-code`, no reference to `@openai/codex`

**Gate:** `grep -r openai/codex modules/paperclip/Dockerfile` returns nothing

---

## T2 — Module variables: swap openai_api_key for vertex vars

**Implements:** R6 (module side)
**File:** `modules/paperclip/variables.tf`
**Depends on:** —
**Parallel:** [P] with T1, T4

**What:**
- Remove `variable "openai_api_key"` block entirely
- Add three new variables:

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

**Done when:**
- `openai_api_key` variable is gone from `modules/paperclip/variables.tf`
- Three new variables are present

**Gate:** `grep openai_api_key modules/paperclip/variables.tf` returns nothing

---

## T3 — Module main.tf: update secret + add K8s SA + update deployment

**Implements:** R2, R3
**File:** `modules/paperclip/main.tf`
**Depends on:** T2
**Parallel:** [P] with T5 (different file)

**What (3 sub-changes in one file):**

**3a — `kubernetes_secret.paperclip_env`:** Remove `OPENAI_API_KEY = var.openai_api_key`. Add:
```hcl
ANTHROPIC_VERTEX_PROJECT_ID = var.vertex_project_id
CLOUD_ML_REGION             = var.vertex_region
```
> Note: If Paperclip's `claude_local` adapter needs an explicit activation env var, add it here. Verify against [adapter docs](https://docs.paperclip.ing/#/reference/adapters/claude-local) before applying.

**3b — New `kubernetes_service_account` resource** (add after `kubernetes_namespace.paperclip`):
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

**3c — `kubernetes_deployment.paperclip` pod spec:** Add inside `spec { template { spec {`:
```hcl
service_account_name = kubernetes_service_account.paperclip.metadata[0].name
```
Add to `depends_on` of the deployment: `kubernetes_service_account.paperclip`

**Done when:**
- Secret has `ANTHROPIC_VERTEX_PROJECT_ID` and `CLOUD_ML_REGION`, no `OPENAI_API_KEY`
- `kubernetes_service_account.paperclip` resource exists with WI annotation
- Deployment references the new service account

**Gate:** `terraform validate` in repo root passes

---

## T4 — Root variables.tf: remove paperclip_openai_api_key

**Implements:** R6 (root side)
**File:** `variables.tf`
**Depends on:** —
**Parallel:** [P] with T1, T2

**What:** Remove `variable "paperclip_openai_api_key"` block from root `variables.tf`.

**Done when:** `grep paperclip_openai_api_key variables.tf` returns nothing

**Gate:** `grep paperclip_openai_api_key variables.tf` returns nothing

---

## T5 — Root main.tf: IAM + WI binding + module call update

**Implements:** R4, R5, R6 (root module call)
**File:** `main.tf`
**Depends on:** T2, T3
**Parallel:** after Wave 1; [P] with T3 if working in different editors, but sequentially safe to do after T3

**What (3 sub-changes in one file):**

**5a — Add IAM member** (under `## WORKLOAD IDENTITY` section):
```hcl
resource "google_project_iam_member" "workloads_vertex_ai" {
  count   = var.cluster_type == "gke" ? 1 : 0
  project = data.google_project.default.id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.gke_workloads[0].email}"
}
```

**5b — Add WI binding for paperclip** (alongside `spark_wi` and `trino_wi`):
```hcl
resource "google_service_account_iam_member" "paperclip_wi" {
  count              = (var.cluster_type == "gke" && var.paperclip) ? 1 : 0
  service_account_id = google_service_account.gke_workloads[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:jusl-496520.svc.id.goog[paperclip/paperclip]"
  depends_on         = [module.paperclip]
}
```

**5c — Update `module "paperclip"` call:** Drop `openai_api_key`, add three new args:
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

**Done when:**
- `workloads_vertex_ai` IAM resource exists
- `paperclip_wi` WI binding resource exists
- `module.paperclip` call has no `openai_api_key`, has all three new args

**Gate:** `terraform validate` passes; `grep openai modules/paperclip/main.tf main.tf variables.tf` returns nothing

---

## Final Gate (all tasks done)

```bash
# No openai references anywhere in the feature's files
grep -r openai modules/paperclip/ main.tf variables.tf

# Terraform validates cleanly
terraform validate

# Plan shows expected additions (IAM, WI binding, K8s SA, new env vars)
# and no unexpected removals of unrelated resources
terraform plan
```
