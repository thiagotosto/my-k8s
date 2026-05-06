output "trino_namespace" {
  description = "Namespace where Trino is deployed"
  value       = kubernetes_namespace.trino.metadata[0].name
}

output "trino_release_name" {
  description = "Helm release name of Trino"
  value       = helm_release.trino.name
}

output "trino_version" {
  description = "Deployed Trino chart version"
  value       = helm_release.trino.version
}
