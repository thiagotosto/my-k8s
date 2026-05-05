resource "kubernetes_namespace" "spark" {
  metadata {
    name = var.spark_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_service_account" "spark" {
  metadata {
    name      = "spark"
    namespace = kubernetes_namespace.spark.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "spark_operator" {
  name       = "spark-operator"
  repository = "https://kubeflow.github.io/spark-operator"
  chart      = "spark-operator"
  version    = var.spark_operator_version
  namespace  = kubernetes_namespace.spark.metadata[0].name

  set = concat([
    {
      name  = "webhook.enable"
      value = "true"
    },
    {
      name  = "spark.jobNamespaces[0]"
      value = var.spark_namespace
    },
    {
      name  = "controller.replicas"
      value = tostring(var.controller_replicas)
    }
    ],
    [for k, v in var.extra_helm_values : {
      name  = k
      value = v
    }]
  )

  depends_on = [kubernetes_namespace.spark]
}
