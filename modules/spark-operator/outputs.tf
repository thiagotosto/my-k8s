output "spark_operator_namespace" {
  description = "Namespace where spark-operator is deployed"
  value       = kubernetes_namespace.spark.metadata[0].name
}

output "spark_operator_release_name" {
  description = "Helm release name of the spark-operator"
  value       = helm_release.spark_operator.name
}

output "spark_operator_version" {
  description = "Deployed spark-operator chart version"
  value       = helm_release.spark_operator.version
}
