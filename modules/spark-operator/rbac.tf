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
    resources  = ["pods", "services", "configmaps", "persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "create", "delete", "deletecollection", "update", "patch"]
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