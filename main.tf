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
  }
}


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
  source = "${path.root}/modules/trino"

  trino_namespace = "trino"
}

module "spark-operator" {
  count  = var.spark_operator ? 1 : 0
  source = "${path.root}/modules/spark-operator"

  spark_namespace = "spark-jobs"
}