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

variable "admin_members" {
  description = "List of IAM members with roles/storage.objectAdmin on the bucket (e.g. user:you@gmail.com)"
  type        = list(string)
  default     = []
}

