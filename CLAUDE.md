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
