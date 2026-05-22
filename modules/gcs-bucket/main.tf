resource "google_storage_bucket" "thiagos_lake" {
  name                        = var.bucket_name
  location                    = var.location
  uniform_bucket_level_access = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_storage_bucket_iam_member" "admin_members" {
  for_each = toset(var.admin_members)
  bucket   = google_storage_bucket.thiagos_lake.name
  role     = "roles/storage.objectAdmin"
  member   = each.value
}

