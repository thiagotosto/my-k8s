terraform {
  required_version = ">= 1.3.0"

  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "kubectl" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}
