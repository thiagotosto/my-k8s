# my-k8s

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

## Architecture decisions

### root
- Kind cluster resources and top-level module wiring live here.

### modules/
- Define operators and Helm installations as Terraform HCL resources.
- Use the `hashicorp/kubernetes` provider.

### apps/
- Define application instances (SparkApplication, FlinkCluster, etc.) as raw YAML files.
- Use the `gavinbunney/kubectl` provider with `kubectl_manifest` to apply them.

### apps/spark/
- Spark jobs are organized under `jobs/<job-name>/` — each subfolder needs a `job.py` and a `spark.yaml`.
- `script.tf` auto-discovers all jobs via `fileset` and creates a ConfigMap + SparkApplication for each.
- ConfigMap naming convention: `spark-<job-name>-script` — the job's `spark.yaml` must reference this name.
- Use the `excluded_jobs` variable in `terraform.tfvars` to skip specific jobs without deleting them.
