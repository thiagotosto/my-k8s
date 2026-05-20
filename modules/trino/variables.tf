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

variable "gcs_secret_name" {
  description = "Name of the Kubernetes secret containing GCS ADC credentials"
  type        = string
}

variable "gcs_bucket" {
  description = "GCS bucket name where Lance tables are stored"
  type        = string
  default     = "justeam"
}

variable "credentials_path" {
  description = "Path to GCS Application Default Credentials JSON file on the local machine"
  type        = string
  default     = "~/.config/gcloud/application_default_credentials.json"
}

variable "ar_repository" {
  description = "Artifact Registry repository URL for Docker images"
  type        = string
  default     = "us-central1-docker.pkg.dev/jusl-496520/my-k8s"
}

variable "workload_identity_sa_email" {
  description = "GCP SA email for Workload Identity annotation on the Trino service account"
  type        = string
  default     = ""
}
