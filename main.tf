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
  project = "jusl-496520"
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
    workload_pool = "jusl-496520.svc.id.goog"
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
    machine_type = "e2-standard-2"

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
    spot = true

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

## ARTIFACT REGISTRY
data "google_project" "default" {}

resource "google_artifact_registry_repository" "my_k8s" {
  count         = var.cluster_type == "gke" ? 1 : 0
  location      = var.gcp_region
  repository_id = "my-k8s"
  format        = "DOCKER"
}

resource "google_project_iam_member" "ar_reader" {
  count   = var.cluster_type == "gke" ? 1 : 0
  project = data.google_project.default.id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${data.google_project.default.number}-compute@developer.gserviceaccount.com"
}

## WORKLOAD IDENTITY
resource "google_service_account" "gke_workloads" {
  count      = var.cluster_type == "gke" ? 1 : 0
  account_id = "gke-workloads"
}

resource "google_project_iam_member" "workloads_gcs" {
  count   = var.cluster_type == "gke" ? 1 : 0
  project = data.google_project.default.id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.gke_workloads[0].email}"
}

resource "google_service_account_iam_member" "spark_wi" {
  count              = var.cluster_type == "gke" ? 1 : 0
  service_account_id = google_service_account.gke_workloads[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:jusl-496520.svc.id.goog[spark-jobs/spark]"
  depends_on         = [module.spark-operator]
}

resource "google_service_account_iam_member" "trino_wi" {
  count              = var.cluster_type == "gke" ? 1 : 0
  service_account_id = google_service_account.gke_workloads[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:jusl-496520.svc.id.goog[trino/trino]"
  depends_on         = [module.trino]
}

## MODULES
module "trino" {
  count  = var.trino ? 1 : 0
  source = "./modules/trino"

  trino_namespace            = "trino"
  gcs_secret_name            = "gcs-adc"
  workload_identity_sa_email = try(google_service_account.gke_workloads[0].email, "")
}

module "juslake_gcs_bucket" {
  count  = (var.gcs_bucket && var.trino) ? 1 : 0
  source = "./modules/gcs-bucket"

  bucket_name   = "justeam"
  admin_members = ["user:tostotech10@gmail.com"]
}

module "spark-operator" {
  count  = var.spark_operator ? 1 : 0
  source = "./modules/spark-operator"

  spark_namespace            = "spark-jobs"
  workload_identity_sa_email = try(google_service_account.gke_workloads[0].email, "")
}

module "cases_pdf_processor" {
  count          = var.cases_pdf_processor ? 1 : 0
  source         = "./modules/cases-pdf-processor"
  project_id     = data.google_project.default.project_id
  project_number = data.google_project.default.number
  region         = var.gcp_region
}
