resource "google_service_account" "lakehouse_mcp" {
  account_id = "lakehouse-mcp"
  project    = var.project
}

resource "google_artifact_registry_repository" "lakehouse_mcp" {
  location      = var.region
  repository_id = "lakehouse-mcp"
  format        = "DOCKER"
}

module "base_image" {
  source        = "../../modules/legal-embeddings-base"
  ar_repository = "${var.region}-docker.pkg.dev/${var.project}/my-k8s"
}

locals {
  image_tag = substr(sha256("${filesha256("${path.module}/Dockerfile")}${filesha256("${path.module}/pyproject.toml")}${filesha256("${path.module}/server.py")}${module.base_image.image_uri}"), 0, 8)
  image_uri = "${var.region}-docker.pkg.dev/${var.project}/lakehouse-mcp/image:${local.image_tag}"
}

resource "null_resource" "build_push" {
  triggers = {
    dockerfile     = filesha256("${path.module}/Dockerfile")
    pyproject_toml = filesha256("${path.module}/pyproject.toml")
    server_py      = filesha256("${path.module}/server.py")
    base_image     = module.base_image.image_uri
  }

  provisioner "local-exec" {
    command = "docker build --build-arg BASE_IMAGE=${module.base_image.image_uri} -t ${local.image_uri} ${path.module} && docker push ${local.image_uri}"
  }

  depends_on = [google_artifact_registry_repository.lakehouse_mcp, module.base_image]
}

resource "google_storage_bucket_iam_member" "lakehouse_mcp_gcs_viewer" {
  bucket = var.gcs_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.lakehouse_mcp.email}"
}

resource "google_service_account_iam_binding" "workload_identity" {
  service_account_id = google_service_account.lakehouse_mcp.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project}.svc.id.goog[lakehouse-mcp/lakehouse-mcp]",
  ]
}

output "image_uri" {
  value = local.image_uri
}
