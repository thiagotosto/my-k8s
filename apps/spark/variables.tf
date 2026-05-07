variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "kind-my-cluster"
}

variable "excluded_jobs" {
  description = "Job names to skip when deploying"
  type        = list(string)
  default     = []
}
