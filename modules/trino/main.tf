resource "kubernetes_namespace" "trino" {
  metadata {
    name = var.trino_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_secret" "gcs_adc" {
  metadata {
    name      = var.gcs_secret_name
    namespace = kubernetes_namespace.trino.metadata[0].name
  }

  data = {
    "application_default_credentials.json" = file(pathexpand(var.credentials_path))
  }

  depends_on = [kubernetes_namespace.trino]
}

resource "helm_release" "trino" {
  name       = "trino"
  repository = "https://trinodb.github.io/charts"
  chart      = "trino"
  version    = var.trino_version
  namespace  = kubernetes_namespace.trino.metadata[0].name

  values = [
    templatefile("${path.module}/values.yaml", {
      ar_repository              = var.ar_repository
      gcs_bucket                 = var.gcs_bucket
      gcs_secret_name            = var.gcs_secret_name
      workload_identity_sa_email = var.workload_identity_sa_email
    })
  ]

  set = concat([
    {
      name  = "server.workers"
      value = tostring(var.worker_replicas)
    },
    {
      name  = "coordinator.jvm.maxHeapSize"
      value = var.coordinator_heap_size
    },
    {
      name  = "worker.jvm.maxHeapSize"
      value = var.worker_heap_size
    }
    ],
    [for k, v in var.extra_helm_values : {
      name  = k
      value = v
    }]
  )

  depends_on = [kubernetes_namespace.trino, kubernetes_secret.gcs_adc, null_resource.trino_custom_image]
}
