terraform {}

locals {
  indexer_image   = "${var.region}-docker.pkg.dev/${var.project_id}/cases-pdf-indexer/image:latest"
  converter_image = "${var.region}-docker.pkg.dev/${var.project_id}/cases-pdf-converter/image:latest"
}

## PUB/SUB

resource "google_pubsub_topic" "cases_pdf_doc_events" {
  name = "cases-pdf-doc-events"
}

resource "google_pubsub_subscription" "cases_pdf_doc_events_sub" {
  name                 = "cases-pdf-doc-events-sub"
  topic                = google_pubsub_topic.cases_pdf_doc_events.id
  ack_deadline_seconds = 600
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

resource "google_project_iam_member" "indexer_eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.indexer.email}"
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

resource "google_pubsub_subscription_iam_member" "converter_subscriber" {
  subscription = google_pubsub_subscription.cases_pdf_doc_events_sub.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.converter.email}"
}

resource "google_project_iam_member" "converter_eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.converter.email}"
}

resource "google_project_iam_member" "converter_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.converter.email}"
}

## IAM — EVENTARC AGENTS

resource "google_project_iam_member" "gcs_sa_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${var.project_number}@gs-project-accounts.iam.gserviceaccount.com"
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
          memory = "512Mi"
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

## EVENTARC TRIGGERS

resource "google_eventarc_trigger" "indexer" {
  name     = "cases-pdf-indexer-trigger"
  location = var.region
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  matching_criteria {
    attribute = "bucket"
    value     = "justeam"
  }
  matching_criteria {
    attribute = "subject"
    value     = "objects/raw/cases_pdf/**"
    operator  = "match-path-pattern"
  }
  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.indexer.name
      region  = var.region
    }
  }
  service_account = google_service_account.indexer.email
}

resource "google_eventarc_trigger" "converter" {
  name     = "cases-pdf-converter-trigger"
  location = var.region
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }
  transport {
    pubsub {
      topic = google_pubsub_topic.cases_pdf_doc_events.id
    }
  }
  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.converter.name
      region  = var.region
    }
  }
  service_account = google_service_account.converter.email
}
