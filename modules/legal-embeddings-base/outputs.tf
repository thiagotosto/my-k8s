output "image_uri" {
  value      = local.image_uri
  depends_on = [null_resource.base_image]
}
