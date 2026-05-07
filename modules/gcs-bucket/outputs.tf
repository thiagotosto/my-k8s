output "bucket_name" {
  description = "Name of the GCS bucket"
  value       = google_storage_bucket.thiagos_lake.name
}

