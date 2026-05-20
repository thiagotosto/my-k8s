variable "spark_namespace" {
  description = "Kubernetes namespace for Spark Operator and Spark jobs"
  type        = string
  default     = "spark"
}

variable "spark_operator_version" {
  description = "Helm chart version for spark-operator"
  type        = string
  default     = "2.1.0"
}

variable "controller_replicas" {
  description = "Number of spark-operator controller replicas"
  type        = number
  default     = 1
}

variable "workload_identity_sa_email" {
  description = "GCP SA email for Workload Identity annotation on the Spark service account"
  type        = string
  default     = ""
}

variable "extra_helm_values" {
  description = "Additional Helm values passed as key=value pairs"
  type        = map(string)
  default     = {}
}
