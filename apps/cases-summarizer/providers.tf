terraform {
  required_version = ">= 1.3.0"

  backend "gcs" {
    bucket = "juslake-terraform-state"
    prefix = "terraform/cases-summarizer/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "google" {}

data "google_client_config" "default" {}

provider "kubernetes" {
  config_context = var.kube_context
}
