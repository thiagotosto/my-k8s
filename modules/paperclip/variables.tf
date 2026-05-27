variable "namespace" {
  description = "Kubernetes namespace for Paperclip"
  type        = string
  default     = "paperclip"
}

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

variable "better_auth_secret" {
  description = "Auth secret used by Paperclip's authentication layer"
  type        = string
  sensitive   = true
  default     = "paperclip-poc-secret"
}

variable "postgres_password" {
  description = "Password for the PostgreSQL paperclip user"
  type        = string
  sensitive   = true
  default     = "paperclip"
}

variable "ar_repository" {
  description = "Artifact Registry base URL (e.g. us-central1-docker.pkg.dev/PROJECT/REPO)"
  type        = string
}

variable "paperclip_git_ref" {
  description = "Git branch or tag to build the Paperclip image from"
  type        = string
  default     = "main"
}
