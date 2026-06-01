## SERVICE ACCOUNT

resource "google_service_account" "cases_summarizer" {
  account_id = "cases-summarizer"
}

## IAM — GCS

resource "google_storage_bucket_iam_member" "cases_summarizer_gcs_viewer" {
  bucket = var.gcs_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.cases_summarizer.email}"
  condition {
    title      = "cases_summarizer_source_prefix"
    expression = "resource.name.startsWith(\"projects/_/buckets/${var.gcs_bucket}/objects/raw/cases_pdf/\")"
  }
}

resource "google_storage_bucket_iam_member" "cases_summarizer_gcs_admin" {
  bucket = var.gcs_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cases_summarizer.email}"
  condition {
    title      = "cases_summarizer_sandbox_prefix"
    expression = "resource.name.startsWith(\"projects/_/buckets/${var.gcs_bucket}/objects/sandbox/\")"
  }
}

## PUB/SUB

resource "google_pubsub_subscription" "cases_summarizer" {
  name  = "cases-summarizer-sub"
  topic = var.gcs_events_topic

  ack_deadline_seconds = 600

  dead_letter_policy {
    dead_letter_topic     = var.dlq_topic
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

resource "google_pubsub_subscription_iam_member" "cases_summarizer_subscriber" {
  subscription = google_pubsub_subscription.cases_summarizer.id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.cases_summarizer.email}"
}
