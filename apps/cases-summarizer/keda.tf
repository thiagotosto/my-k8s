resource "kubernetes_manifest" "trigger_auth" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "TriggerAuthentication"
    metadata = {
      name      = "cases-summarizer-trigger-auth"
      namespace = "cases-summarizer"
    }
    spec = {
      podIdentity = {
        provider = "gcp"
      }
    }
  }
}

resource "kubernetes_manifest" "scaled_object" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "cases-summarizer-scaled-object"
      namespace = "cases-summarizer"
    }
    spec = {
      scaleTargetRef = {
        name = "cases-summarizer"
      }
      minReplicaCount = 0
      maxReplicaCount = 5
      triggers = [{
        type = "gcp-pubsub"
        metadata = {
          subscriptionName            = "cases-summarizer-sub"
          targetMessagesPerWorker     = "1"
          activationMessagesPerWorker = "1"
        }
        authenticationRef = {
          name = "cases-summarizer-trigger-auth"
        }
      }]
    }
  }

  depends_on = [kubernetes_manifest.trigger_auth]
}
