resource "kubernetes_namespace" "cases_summarizer" {
  metadata {
    name = "cases-summarizer"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_service_account" "cases_summarizer" {
  metadata {
    name      = "cases-summarizer"
    namespace = kubernetes_namespace.cases_summarizer.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = var.sa_email
    }
  }
}

resource "kubernetes_secret" "cases_summarizer_env" {
  metadata {
    name      = "cases-summarizer-env"
    namespace = kubernetes_namespace.cases_summarizer.metadata[0].name
  }

  data = {
    OPENAI_API_KEY = var.openai_api_key
    OPENAI_MODEL   = "gpt-4o-mini"
  }
}

resource "kubernetes_deployment" "cases_summarizer" {
  metadata {
    name      = "cases-summarizer"
    namespace = kubernetes_namespace.cases_summarizer.metadata[0].name
    labels = {
      app = "cases-summarizer"
    }
  }

  spec {
    replicas = 0

    selector {
      match_labels = {
        app = "cases-summarizer"
      }
    }

    template {
      metadata {
        labels = {
          app = "cases-summarizer"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.cases_summarizer.metadata[0].name

        container {
          name  = "cases-summarizer"
          image = local.image_uri

          env_from {
            secret_ref {
              name = kubernetes_secret.cases_summarizer_env.metadata[0].name
            }
          }

          env {
            name  = "GCS_BUCKET"
            value = var.gcs_bucket
          }

          env {
            name  = "LANCE_URI"
            value = "gs://${var.gcs_bucket}/sandbox"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.cases_summarizer,
    kubernetes_service_account.cases_summarizer,
    kubernetes_secret.cases_summarizer_env,
    null_resource.build_push,
  ]
}
