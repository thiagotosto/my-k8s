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

