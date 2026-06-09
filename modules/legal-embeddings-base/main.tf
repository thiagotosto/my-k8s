locals {
  base_tag  = substr(filesha256("${path.module}/Dockerfile"), 0, 8)
  image_uri = "${var.ar_repository}/legal-embeddings-base:${local.base_tag}"
}
