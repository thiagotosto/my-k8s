locals {
  image_tag = substr(sha256("${filesha256("${path.module}/Dockerfile")}${filesha256("${path.module}/pyproject.toml")}"), 0, 8)
  image_uri = "${var.region}-docker.pkg.dev/${var.project}/cases-summarizer/image:${local.image_tag}"
}

resource "google_artifact_registry_repository" "cases_summarizer" {
  location      = var.region
  repository_id = "cases-summarizer"
  format        = "DOCKER"
}

resource "null_resource" "build_push" {
  triggers = {
    dockerfile     = filesha256("${path.module}/Dockerfile")
    pyproject_toml = filesha256("${path.module}/pyproject.toml")
  }

  provisioner "local-exec" {
    command = "docker build -t ${local.image_uri} ${path.module} && docker push ${local.image_uri}"
  }

  depends_on = [google_artifact_registry_repository.cases_summarizer]
}

resource "google_service_account_iam_binding" "workload_identity" {
  service_account_id = "projects/${var.project}/serviceAccounts/${var.sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project}.svc.id.goog[cases-summarizer/cases-summarizer]",
  ]
}

output "image_uri" {
  value = local.image_uri
}
