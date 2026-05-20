resource "kubectl_manifest" "nfs_storage_pvc" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "nfs-server-storage"
      namespace = "spark-jobs"
    }
    spec = {
      accessModes      = ["ReadWriteOnce"]
      storageClassName = "standard-rwo"
      resources = {
        requests = { storage = "5Gi" }
      }
    }
  })
}

resource "kubectl_manifest" "nfs_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "nfs-server"
      namespace = "spark-jobs"
    }
    spec = {
      replicas = 1
      selector = { matchLabels = { app = "nfs-server" } }
      template = {
        metadata = { labels = { app = "nfs-server" } }
        spec = {
          containers = [{
            name  = "nfs-server"
            image = "itsthenetwork/nfs-server-alpine:latest"
            env   = [{ name = "SHARED_DIRECTORY", value = "/exports" }]
            ports = [{ containerPort = 2049 }]
            securityContext = { privileged = true }
            volumeMounts    = [{ name = "nfs-storage", mountPath = "/exports" }]
          }]
          volumes = [{
            name = "nfs-storage"
            persistentVolumeClaim = { claimName = "nfs-server-storage" }
          }]
        }
      }
    }
  })
  depends_on = [kubectl_manifest.nfs_storage_pvc]
}

resource "kubectl_manifest" "nfs_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "nfs-server"
      namespace = "spark-jobs"
    }
    spec = {
      selector = { app = "nfs-server" }
      ports    = [{ name = "nfs", port = 2049 }]
    }
  })
}

# Creates PV + PVC using the NFS service ClusterIP resolved at apply time.
resource "null_resource" "spark_models_pv_pvc" {
  triggers = {
    nfs_service_uid = kubectl_manifest.nfs_service.uid
  }

  provisioner "local-exec" {
    command = <<-EOT
      NFS_IP=$(kubectl get svc nfs-server -n spark-jobs -o jsonpath='{.spec.clusterIP}')
      sed "s/NFS_SERVER/$NFS_IP/" << 'YAML' | kubectl apply -f -
      apiVersion: v1
      kind: PersistentVolume
      metadata:
        name: spark-models-pv
      spec:
        capacity:
          storage: 4Gi
        accessModes:
          - ReadWriteMany
        persistentVolumeReclaimPolicy: Retain
        storageClassName: ""
        nfs:
          server: NFS_SERVER
          path: /
      ---
      apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: spark-models-pvc
        namespace: spark-jobs
      spec:
        accessModes:
          - ReadWriteMany
        storageClassName: ""
        resources:
          requests:
            storage: 4Gi
        volumeName: spark-models-pv
      YAML
    EOT
  }

  depends_on = [kubectl_manifest.nfs_service]
}

resource "null_resource" "download_models" {
  triggers = {
    pvc_setup = null_resource.spark_models_pv_pvc.id
    image_tag = "${var.ar_repository}/spark-lance-gcs:4.0.2"
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl delete job download-models -n spark-jobs --ignore-not-found
      kubectl rollout status deployment/nfs-server -n spark-jobs --timeout=120s
      kubectl apply -f - << 'JOB'
      apiVersion: batch/v1
      kind: Job
      metadata:
        name: download-models
        namespace: spark-jobs
      spec:
        ttlSecondsAfterFinished: 600
        backoffLimit: 3
        template:
          spec:
            restartPolicy: OnFailure
            containers:
            - name: downloader
              image: ${var.ar_repository}/spark-lance-gcs:4.0.2
              imagePullPolicy: IfNotPresent
              env:
              - name: HF_HOME
                value: /models
              - name: TORCH_HOME
                value: /models/torch
              command:
              - sh
              - -c
              - |
                python3 -c "
                import pathlib
                marker = pathlib.Path('/models/.downloaded')
                if not marker.exists():
                    from sentence_transformers import SentenceTransformer
                    SentenceTransformer('all-MiniLM-L6-v2')
                    import open_clip
                    open_clip.create_model_and_transforms('ViT-B-32', pretrained='openai')
                    marker.touch()
                    print('Models downloaded')
                else:
                    print('Models already present, skipping')
                "
              volumeMounts:
              - name: models
                mountPath: /models
            volumes:
            - name: models
              persistentVolumeClaim:
                claimName: spark-models-pvc
      JOB
    EOT
  }

  depends_on = [null_resource.spark_models_pv_pvc]
}
