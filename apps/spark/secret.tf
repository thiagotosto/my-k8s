resource "kubectl_manifest" "gcs_adc_secret" {
  sensitive_fields = ["stringData"]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "gcs-adc"
      namespace = "spark-jobs"
    }
    type = "Opaque"
    stringData = {
      "application_default_credentials.json" = file(pathexpand("~/.config/gcloud/application_default_credentials.json"))
    }
  })
}

resource "kubectl_manifest" "gcs_sa_secret" {
  sensitive_fields = ["stringData"]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "gcs-sa"
      namespace = "spark-jobs"
    }
    type = "Opaque"
    stringData = {
      "application_default_credentials.json" = file("${path.module}/jobs/multimodal-products/credentials/my-k8s-495416-f42aa843ffe3.json")
    }
  })
}

