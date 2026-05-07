terraform {
  backend "gcs" {
    bucket = "thiago-terraform-state"
    prefix = "terraform/state"
  }
  required_providers {
    kind = {
      source  = "justenwalker/kind"
      version = "0.17.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}


provider "google" {}

provider "null" {}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}

## CLUSTER
resource "kind_cluster" "my-cluster" {
  name = "my-cluster"
  config = <<-EOF
        apiVersion: kind.x-k8s.io/v1alpha4
        kind: Cluster
        nodes:
        - role: control-plane
        - role: worker
        - role: worker
    EOF
}

## MODULES
module "trino" {
  count  = var.trino ? 1 : 0
  source = "./modules/trino"

  trino_namespace = "trino"
  gcs_secret_name = "gcs-adc"
}

module "gcs_bucket" {
  count  = (var.gcs_bucket && var.trino) ? 1 : 0
  source = "./modules/gcs-bucket"
}

module "spark-operator" {
  count  = var.spark_operator ? 1 : 0
  source = "./modules/spark-operator"

  spark_namespace = "spark-jobs"
}