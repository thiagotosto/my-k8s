resource "null_resource" "base_image" {
  triggers = {
    dockerfile = filesha256("${path.module}/Dockerfile")
  }

  provisioner "local-exec" {
    command = "docker build -t ${local.image_uri} ${path.module} && docker push ${local.image_uri}"
  }
}
