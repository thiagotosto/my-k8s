resource "null_resource" "spark_custom_image" {
  triggers = {
    dockerfile_md5 = filemd5("${path.module}/Dockerfile")
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker build -t spark-lance-gcs:3.5.0 ${path.module}
      kind load docker-image spark-lance-gcs:3.5.0 --name my-cluster
    EOT
  }
}
