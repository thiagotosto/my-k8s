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

resource "kubernetes_role" "spark_driver" {
  metadata {
    name      = "spark-driver"
    namespace = kubernetes_namespace.spark.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "delete", "update", "patch"]
  }
}

resource "kubernetes_role_binding" "spark_driver" {
  metadata {
    name      = "spark-driver"
    namespace = kubernetes_namespace.spark.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.spark_driver.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.spark.metadata[0].name
    namespace = kubernetes_namespace.spark.metadata[0].name
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
      name  = "sparkJobNamespace"
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
