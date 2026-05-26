resource "kubernetes_namespace" "paperclip" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

## PostgreSQL
resource "kubernetes_secret" "postgres_creds" {
  metadata {
    name      = "postgres-creds"
    namespace = kubernetes_namespace.paperclip.metadata[0].name
  }

  data = {
    POSTGRES_USER     = "paperclip"
    POSTGRES_PASSWORD = var.postgres_password
    POSTGRES_DB       = "paperclip"
  }
}

resource "kubernetes_manifest" "postgres_statefulset" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "StatefulSet"
    metadata = {
      name      = "postgres"
      namespace = var.namespace
      labels    = { app = "postgres" }
    }
    spec = {
      serviceName = "postgres"
      replicas    = 1
      selector = {
        matchLabels = { app = "postgres" }
      }
      template = {
        metadata = {
          labels = { app = "postgres" }
        }
        spec = {
          containers = [{
            name  = "postgres"
            image = "postgres:17-alpine"
            envFrom = [{
              secretRef = { name = "postgres-creds" }
            }]
            env = [{
              name  = "PGDATA"
              value = "/var/lib/postgresql/data/pgdata"
            }]
            ports = [{ containerPort = 5432 }]
            volumeMounts = [{
              name      = "pgdata"
              mountPath = "/var/lib/postgresql/data"
            }]
            readinessProbe = {
              exec               = { command = ["pg_isready", "-U", "paperclip"] }
              initialDelaySeconds = 5
              periodSeconds       = 5
            }
          }]
        }
      }
      volumeClaimTemplates = [{
        metadata = { name = "pgdata" }
        spec = {
          accessModes = ["ReadWriteOnce"]
          resources   = { requests = { storage = "5Gi" } }
        }
      }]
    }
  }

  computed_fields = [
    "spec.template.spec.containers[0].resources",
    "spec.template.spec.containers[0].terminationMessagePath",
    "spec.template.spec.containers[0].terminationMessagePolicy",
    "spec.template.spec.containers[0].imagePullPolicy",
    "spec.volumeClaimTemplates[0].spec.storageClassName",
    "spec.volumeClaimTemplates[0].spec.volumeMode",
  ]

  depends_on = [kubernetes_secret.postgres_creds]
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "postgres"
    namespace = kubernetes_namespace.paperclip.metadata[0].name
  }

  spec {
    selector = {
      app = "postgres"
    }

    port {
      port        = 5432
      target_port = 5432
    }

    type = "ClusterIP"
  }
}

## Paperclip image build

resource "null_resource" "paperclip_image" {
  triggers = {
    git_ref = var.paperclip_git_ref
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf /tmp/paperclip-build && \
      git clone --depth=1 https://github.com/paperclipai/paperclip /tmp/paperclip-build && \
      docker build -t ${var.ar_repository}/paperclip:${var.paperclip_git_ref} /tmp/paperclip-build && \
      docker push ${var.ar_repository}/paperclip:${var.paperclip_git_ref}
    EOT
  }
}

## Paperclip server

resource "kubernetes_secret" "paperclip_env" {
  metadata {
    name      = "paperclip-env"
    namespace = kubernetes_namespace.paperclip.metadata[0].name
  }

  data = {
    OPENAI_API_KEY     = var.openai_api_key
    BETTER_AUTH_SECRET = var.better_auth_secret
    DATABASE_URL       = "postgresql://paperclip:${var.postgres_password}@postgres.${var.namespace}.svc.cluster.local:5432/paperclip"
  }
}

resource "kubernetes_persistent_volume_claim" "paperclip_data" {
  metadata {
    name      = "paperclip-data"
    namespace = kubernetes_namespace.paperclip.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }

  wait_until_bound = false
}

resource "kubernetes_deployment" "paperclip" {
  metadata {
    name      = "paperclip"
    namespace = kubernetes_namespace.paperclip.metadata[0].name
    labels = {
      app = "paperclip"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "paperclip"
      }
    }

    template {
      metadata {
        labels = {
          app = "paperclip"
        }
      }

      spec {
        init_container {
          name    = "init-permissions"
          image   = "busybox:latest"
          command = ["sh", "-c", "mkdir -p /paperclip/instances/default/logs && chmod -R 777 /paperclip"]
          volume_mount {
            name       = "paperclip-data"
            mount_path = "/paperclip"
          }
        }

        container {
          name  = "paperclip"
          image = "${var.ar_repository}/paperclip:${var.paperclip_git_ref}"

          env_from {
            secret_ref {
              name = kubernetes_secret.paperclip_env.metadata[0].name
            }
          }

          env {
            name  = "NODE_ENV"
            value = "production"
          }

          env {
            name  = "HOST"
            value = "0.0.0.0"
          }

          env {
            name  = "PORT"
            value = "3100"
          }

          env {
            name  = "SERVE_UI"
            value = "true"
          }

          env {
            name  = "PAPERCLIP_MIGRATION_AUTO_APPLY"
            value = "true"
          }

          env {
            name  = "PAPERCLIP_DEPLOYMENT_MODE"
            value = "authenticated"
          }

          env {
            name  = "PAPERCLIP_PUBLIC_URL"
            value = "http://localhost:3100"
          }

          port {
            container_port = 3100
          }

          volume_mount {
            name       = "paperclip-data"
            mount_path = "/paperclip"
          }

          readiness_probe {
            tcp_socket {
              port = 3100
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }
        }

        volume {
          name = "paperclip-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.paperclip_data.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.postgres_statefulset,
    kubernetes_secret.paperclip_env,
    kubernetes_persistent_volume_claim.paperclip_data,
    null_resource.paperclip_image,
  ]
}

resource "kubernetes_service" "paperclip" {
  metadata {
    name      = "paperclip"
    namespace = kubernetes_namespace.paperclip.metadata[0].name
  }

  spec {
    selector = {
      app = "paperclip"
    }

    port {
      port        = 3100
      target_port = 3100
    }

    type = "ClusterIP"
  }
}
