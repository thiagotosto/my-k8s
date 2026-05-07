locals {
  all_jobs = toset([
    for f in fileset("${path.module}/jobs", "*/spark.yaml") :
    dirname(f)
  ])
  jobs = setsubtract(local.all_jobs, toset(var.excluded_jobs))
}

resource "kubectl_manifest" "spark_script" {
  for_each = local.jobs

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "spark-${each.key}-script"
      namespace = "spark-jobs"
    }
    data = {
      "job.py" = file("${path.module}/jobs/${each.key}/job.py")
    }
  })
}

resource "kubectl_manifest" "spark_application" {
  for_each = local.jobs

  yaml_body  = file("${path.module}/jobs/${each.key}/spark.yaml")
  depends_on = [
    kubectl_manifest.spark_script,
    null_resource.spark_custom_image,
  ]
}
