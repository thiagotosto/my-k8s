variable "spark_operator" {
  type    = bool
  default = true
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubernetes context to use from the kubeconfig"
  type        = string
  default     = null
}