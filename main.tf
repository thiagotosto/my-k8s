terraform {
  backend "gcs" {
    bucket = "juslake-terraform-state"
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

provider "google" {
  project = "my-k8s-495416"
}

provider "null" {}

data "google_client_config" "default" {}

locals {
  gke_endpoint = try(google_container_cluster.my_cluster[0].endpoint, "")
  gke_ca_cert = var.cluster_type == "gke" ? try(
    base64decode(google_container_cluster.my_cluster[0].master_auth[0].cluster_ca_certificate),
    null
  ) : null
}

provider "kubernetes" {
  host                   = var.cluster_type == "gke" ? "https://${local.gke_endpoint}" : null
  token                  = var.cluster_type == "gke" ? data.google_client_config.default.access_token : null
  cluster_ca_certificate = local.gke_ca_cert
  config_path            = var.cluster_type == "kind" ? var.kubeconfig_path : null
  config_context         = var.cluster_type == "kind" ? var.kube_context : null
}

provider "helm" {
  kubernetes = {
    host                   = var.cluster_type == "gke" ? "https://${local.gke_endpoint}" : null
    token                  = var.cluster_type == "gke" ? data.google_client_config.default.access_token : null
    cluster_ca_certificate = local.gke_ca_cert
    config_path            = var.cluster_type == "kind" ? var.kubeconfig_path : null
    config_context         = var.cluster_type == "kind" ? var.kube_context : null
  }
}

## CLUSTER
resource "kind_cluster" "my-cluster" {
  count = var.cluster_type == "kind" ? 1 : 0
  name  = "my-cluster"
  config = <<-EOF
        apiVersion: kind.x-k8s.io/v1alpha4
        kind: Cluster
        nodes:
        - role: control-plane
        - role: worker
        - role: worker
    EOF
}

resource "google_container_cluster" "my_cluster" {
  count    = var.cluster_type == "gke" ? 1 : 0
  name     = "my-cluster"
  location = var.gcp_zone

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  workload_identity_config {
    workload_pool = "my-k8s-495416.svc.id.goog"
  }
}

resource "google_container_node_pool" "system" {
  count    = var.cluster_type == "gke" ? 1 : 0
  name     = "system"
  location = var.gcp_zone
  cluster  = google_container_cluster.my_cluster[0].name

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    machine_type = "e2-standard-4"

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}

resource "google_container_node_pool" "spark" {
  count    = var.cluster_type == "gke" ? 1 : 0
  name     = "spark"
  location = var.gcp_zone
  cluster  = google_container_cluster.my_cluster[0].name

  autoscaling {
    min_node_count = 0
    max_node_count = 10
  }

  node_config {
    machine_type = "e2-standard-4"

    labels = {
      pool = "spark"
    }

    taint {
      key    = "pool"
      value  = "spark"
      effect = "NO_SCHEDULE"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
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

module "juslake_gcs_bucket" {
  count  = (var.gcs_bucket && var.trino) ? 1 : 0
  source = "./modules/gcs-bucket"

  bucket_name = "juslake"
}

module "spark-operator" {
  count  = var.spark_operator ? 1 : 0
  source = "./modules/spark-operator"

  spark_namespace = "spark-jobs"
}
