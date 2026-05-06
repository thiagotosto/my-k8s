resource "kubernetes_namespace" "trino" {
  metadata {
    name = var.trino_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "trino" {
  name       = "trino"
  repository = "https://trinodb.github.io/charts"
  chart      = "trino"
  version    = var.trino_version
  namespace  = kubernetes_namespace.trino.metadata[0].name

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

  depends_on = [kubernetes_namespace.trino]
}
