resource "null_resource" "spark_custom_image" {
  triggers = {
    dockerfile_md5 = filemd5("${path.module}/Dockerfile")
    lib_hash       = sha1(join("", [for f in sort(fileset("${path.module}/lib", "**")) : filesha1("${path.module}/lib/${f}")]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      docker build --pull=false -t ${var.ar_repository}/spark-lance-gcs:4.0.2 ${path.module}
      docker push ${var.ar_repository}/spark-lance-gcs:4.0.2
    EOT
  }
}
