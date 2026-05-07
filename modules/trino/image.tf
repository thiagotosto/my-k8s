resource "null_resource" "trino_custom_image" {
  triggers = {
    dockerfile_md5 = filemd5("${path.module}/Dockerfile")
  }

  provisioner "local-exec" {
    command = "docker build -t trino-lance-gcs:476-v0.2.2 ${path.module} && kind load docker-image trino-lance-gcs:476-v0.2.2 --name my-cluster"
  }
}
