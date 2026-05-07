resource "google_storage_bucket" "thiagos_lake" {
  name     = var.bucket_name
  location = var.location

  lifecycle {
    prevent_destroy = true
  }
}

