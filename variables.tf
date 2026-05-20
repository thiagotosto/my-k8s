variable "cluster_type" {
  description = "Type of Kubernetes cluster to deploy"
  type        = string
  default     = "kind"
  validation {
    condition     = contains(["gke", "kind"], var.cluster_type)
    error_message = "cluster_type must be 'kind' or 'gke'."
  }
}

variable "gcp_region" {
  description = "GCP region for GKE cluster and Artifact Registry"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for GKE cluster"
  type        = string
  default     = "us-central1-a"
}

variable "spark_operator" {
  type    = bool
  default = true
}

variable "trino" {
  type    = bool
  default = true
}

variable "gcs_bucket" {
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
