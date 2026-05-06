resource "kubectl_manifest" "spark_lance_script" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "spark-lance-script"
      namespace = "spark-jobs"
    }
    data = {
      "job.py" = file("${path.module}/job.py")
    }
  })
}

resource "kubectl_manifest" "spark_pi" {
  yaml_body = file("${path.module}/spark-pi.yaml")
  depends_on = [
    kubectl_manifest.spark_lance_script,
    null_resource.spark_custom_image,
  ]
}
