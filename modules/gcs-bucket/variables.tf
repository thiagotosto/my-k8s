variable "bucket_name" {
  description = "Name of the existing GCS bucket"
  type        = string
  default     = "thiagos-lake"
}

variable "location" {
  description = "GCS bucket location (used only for Terraform state alignment after import)"
  type        = string
  default     = "US"
}

