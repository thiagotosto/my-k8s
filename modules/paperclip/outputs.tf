output "namespace" {
  value = kubernetes_namespace.paperclip.metadata[0].name
}

output "port_forward_command" {
  value = "kubectl port-forward -n ${var.namespace} svc/paperclip 3100:3100"
}
