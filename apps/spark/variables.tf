variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "gke_jusl-496520_us-central1-a_my-cluster"
}

variable "ar_repository" {
  description = "Artifact Registry repository URL for Docker images"
  type        = string
  default     = "us-central1-docker.pkg.dev/jusl-496520/my-k8s"
}

variable "excluded_jobs" {
  description = "Job names to skip when deploying"
  type        = list(string)
  default     = []
}
