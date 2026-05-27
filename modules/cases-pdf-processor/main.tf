terraform {}

locals {
  indexer_tag     = substr(md5("${filemd5("${path.module}/src/indexer/Dockerfile")}${filemd5("${path.module}/src/indexer/main.py")}"), 0, 8)
  converter_tag   = substr(md5("${filemd5("${path.module}/src/converter/Dockerfile")}${filemd5("${path.module}/src/converter/main.py")}"), 0, 8)
  indexer_image   = "${var.region}-docker.pkg.dev/${var.project_id}/cases-pdf-indexer/image:${local.indexer_tag}"
  converter_image = "${var.region}-docker.pkg.dev/${var.project_id}/cases-pdf-converter/image:${local.converter_tag}"
}

## PUB/SUB

resource "google_pubsub_topic" "cases_pdf_gcs_events" {
  name = "cases-pdf-gcs-events"
}

resource "google_pubsub_topic" "cases_pdf_gcs_events_dlq" {
  name = "cases-pdf-gcs-events-dlq"
}

resource "google_pubsub_topic" "cases_pdf_doc_events" {
  name = "cases-pdf-doc-events"
}

resource "google_pubsub_topic" "cases_pdf_doc_events_dlq" {
  name = "cases-pdf-doc-events-dlq"
}


## ARTIFACT REGISTRY

resource "google_artifact_registry_repository" "indexer" {
  location      = var.region
  repository_id = "cases-pdf-indexer"
  format        = "DOCKER"
}

resource "google_artifact_registry_repository" "converter" {
  location      = var.region
  repository_id = "cases-pdf-converter"
  format        = "DOCKER"
}

## SERVICE ACCOUNTS

resource "google_service_account" "indexer" {
  account_id = "cases-pdf-indexer"
}

resource "google_service_account" "converter" {
  account_id = "cases-pdf-converter"
}

## IAM — INDEXER

resource "google_storage_bucket_iam_member" "indexer_gcs_viewer" {
  bucket = "justeam"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.indexer.email}"
  condition {
    title      = "indexer_source_prefix"
    expression = "resource.name.startsWith(\"projects/_/buckets/justeam/objects/raw/cases_pdf/\")"
  }
}

resource "google_pubsub_topic_iam_member" "indexer_publisher" {
  topic  = google_pubsub_topic.cases_pdf_doc_events.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.indexer.email}"
}


resource "google_project_iam_member" "indexer_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.indexer.email}"
}

## IAM — CONVERTER

resource "google_storage_bucket_iam_member" "converter_gcs_viewer" {
  bucket = "justeam"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.converter.email}"
  condition {
    title      = "converter_source_prefix"
    expression = "resource.name.startsWith(\"projects/_/buckets/justeam/objects/raw/cases_pdf/\")"
  }
}

resource "google_storage_bucket_iam_member" "converter_gcs_creator" {
  bucket = "justeam"
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.converter.email}"
  condition {
    title      = "converter_output_prefix"
    expression = "resource.name.startsWith(\"projects/_/buckets/justeam/objects/raw/cases_md/\")"
  }
}

resource "google_storage_bucket_iam_member" "converter_gcs_viewer_output" {
  bucket = "justeam"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.converter.email}"
  condition {
    title      = "converter_output_prefix_viewer"
    expression = "resource.name.startsWith(\"projects/_/buckets/justeam/objects/raw/cases_md/\")"
  }
}



resource "google_project_iam_member" "converter_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.converter.email}"
}

## IAM — PUB/SUB AGENTS

resource "google_pubsub_topic_iam_member" "gcs_sa_gcs_events_publisher" {
  topic  = google_pubsub_topic.cases_pdf_gcs_events.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${var.project_number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_pubsub_topic_iam_member" "pubsub_sa_gcs_dlq_publisher" {
  topic  = google_pubsub_topic.cases_pdf_gcs_events_dlq.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_topic_iam_member" "pubsub_sa_doc_dlq_publisher" {
  topic  = google_pubsub_topic.cases_pdf_doc_events_dlq.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "pubsub_sa_indexer_subscriber" {
  subscription = google_pubsub_subscription.indexer.id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "pubsub_sa_converter_subscriber" {
  subscription = google_pubsub_subscription.converter.id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "pubsub_sa_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

## IMAGE BUILDS

resource "null_resource" "indexer_image" {
  triggers = {
    dockerfile = filemd5("${path.module}/src/indexer/Dockerfile")
    main_py    = filemd5("${path.module}/src/indexer/main.py")
  }
  provisioner "local-exec" {
    command = "docker build -t ${local.indexer_image} ${path.module}/src/indexer && docker push ${local.indexer_image}"
  }
  depends_on = [google_artifact_registry_repository.indexer]
}

resource "null_resource" "converter_image" {
  triggers = {
    dockerfile = filemd5("${path.module}/src/converter/Dockerfile")
    main_py    = filemd5("${path.module}/src/converter/main.py")
  }
  provisioner "local-exec" {
    command = "docker build -t ${local.converter_image} ${path.module}/src/converter && docker push ${local.converter_image}"
  }
  depends_on = [google_artifact_registry_repository.converter]
}

## CLOUD RUN SERVICES

resource "google_cloud_run_v2_service" "indexer" {
  name     = "cases-pdf-indexer"
  location = var.region
  template {
    service_account                  = google_service_account.indexer.email
    max_instance_request_concurrency = 1
    timeout                          = "300s"
    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }
    containers {
      image = local.indexer_image
      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.cases_pdf_doc_events.id
      }
      resources {
        limits = {
          memory = "2Gi"
          cpu    = "1"
        }
      }
    }
  }
  depends_on = [null_resource.indexer_image]
}

resource "google_cloud_run_v2_service" "converter" {
  name     = "cases-pdf-converter"
  location = var.region
  template {
    service_account                  = google_service_account.converter.email
    max_instance_request_concurrency = 1
    timeout                          = "3600s"
    scaling {
      min_instance_count = 0
      max_instance_count = var.max_converter_instances
    }
    containers {
      image = local.converter_image
      resources {
        limits = {
          memory = "4Gi"
          cpu    = "2"
        }
      }
    }
  }
  depends_on = [null_resource.converter_image]
}

## GCS NOTIFICATION + PUSH SUBSCRIPTIONS

resource "google_storage_notification" "cases_pdf" {
  bucket             = "justeam"
  payload_format     = "JSON_API_V1"
  topic              = google_pubsub_topic.cases_pdf_gcs_events.id
  event_types        = ["OBJECT_FINALIZE"]
  object_name_prefix = "raw/cases_pdf/"
  depends_on         = [google_pubsub_topic_iam_member.gcs_sa_gcs_events_publisher]
}

resource "google_pubsub_subscription" "indexer" {
  name  = "cases-pdf-indexer-sub"
  topic = google_pubsub_topic.cases_pdf_gcs_events.id

  ack_deadline_seconds = 600

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.cases_pdf_gcs_events_dlq.id
    max_delivery_attempts = var.max_delivery_attempts
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  push_config {
    push_endpoint = google_cloud_run_v2_service.indexer.uri
    oidc_token {
      service_account_email = google_service_account.indexer.email
    }
  }
}

resource "google_pubsub_subscription" "converter" {
  name  = "cases-pdf-converter-sub"
  topic = google_pubsub_topic.cases_pdf_doc_events.id

  ack_deadline_seconds = 600

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.cases_pdf_doc_events_dlq.id
    max_delivery_attempts = var.max_delivery_attempts
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  push_config {
    push_endpoint = google_cloud_run_v2_service.converter.uri
    oidc_token {
      service_account_email = google_service_account.converter.email
    }
  }
}
