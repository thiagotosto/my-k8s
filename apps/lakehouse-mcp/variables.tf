variable "project" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "gcs_bucket" {
  type    = string
  default = "justeam"
}

variable "kube_context" {
  type    = string
  default = "gke_jusl-496520_us-central1-a_my-cluster"
}
