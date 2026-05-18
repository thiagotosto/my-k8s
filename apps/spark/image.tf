resource "null_resource" "spark_custom_image" {
  triggers = {
    dockerfile_md5 = filemd5("${path.module}/Dockerfile")
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker build --pull=false -t spark-lance-gcs:4.0.2 ${path.module}
      kind load docker-image spark-lance-gcs:4.0.2 --name my-cluster
    EOT
  }
}
