resource "kubectl_manifest" "spark_pi" {
  yaml_body = file("${path.module}/spark-pi.yaml")
}
