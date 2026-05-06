terraform {
  required_version = ">= 1.3.0"

  backend "gcs" {
    bucket = "thiago-terraform-state"
    prefix = "terraform/spark-pi/state"
  }

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "kubectl" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}
