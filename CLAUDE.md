# my-k8s

## Design principles

Always create solutions that are:

- **Replayable** — every operation must be idempotent and re-runnable from scratch with the same outcome. Prefer declarative tools (Terraform, Kubernetes manifests) over imperative scripts. Scripts that mutate state must be safe to run twice.
- **Versionable** — all configuration, infrastructure, and application code lives in source control. No manual steps, no out-of-band state. Infrastructure is defined as code; secrets are referenced, never hardcoded.
- **Scalable** — design for growth in data volume, job concurrency, and team size. Prefer parameterized modules over copy-pasted blocks. Avoid hardcoded resource limits or single-node assumptions.

## Folder structure

```
.
├── main.tf          # Kind cluster definition and module calls
├── variables.tf
├── terraform.tfvars
├── modules/         # Operators and Helm installations (e.g. spark-operator, flink-operator)
│   └── <operator>/
└── apps/            # Instances using operators or Helm releases (e.g. SparkApplication, FlinkCluster)
    └── <app>/
        └── spark/                    # Spark jobs app (uses spark-operator)
            ├── Dockerfile            # Custom Spark image (lance + GCS connectors)
            ├── image.tf              # Builds and loads image into Kind cluster
            ├── script.tf             # Dynamically creates ConfigMaps + SparkApplications for all jobs
            ├── secret.tf             # GCS ADC credentials secret
            ├── variables.tf          # kubeconfig_path, kube_context, excluded_jobs
            └── jobs/                 # One subdirectory per Spark job
                └── <job-name>/
                    ├── job.py        # PySpark script
                    └── spark.yaml    # SparkApplication manifest
```