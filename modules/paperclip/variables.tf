variable "namespace" {
  description = "Kubernetes namespace for Paperclip"
  type        = string
  default     = "paperclip"
}

variable "openai_api_key" {
  description = "OpenAI API key for Paperclip"
  type        = string
  sensitive   = true
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
