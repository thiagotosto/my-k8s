variable "trino_namespace" {
  description = "Kubernetes namespace for Trino"
  type        = string
  default     = "trino"
}

variable "trino_version" {
  description = "Helm chart version for trino"
  type        = string
  default     = "0.27.0"
}

variable "worker_replicas" {
  description = "Number of Trino worker replicas"
  type        = number
  default     = 2
}

variable "coordinator_heap_size" {
  description = "JVM max heap size for the coordinator"
  type        = string
  default     = "512M"
}

variable "worker_heap_size" {
  description = "JVM max heap size for each worker"
  type        = string
  default     = "512M"
}

variable "extra_helm_values" {
  description = "Additional Helm values passed as key=value pairs"
  type        = map(string)
  default     = {}
}
