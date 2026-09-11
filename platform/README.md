# Platform Controllers

`platform/base` contains shared Argo CD Applications for pinned upstream Helm charts. Environment overlays provide non-secret capacity and retention settings.

Managed controllers:

- ingress-nginx
- cert-manager
- external-dns
- external-secrets
- metrics-server
- argo-rollouts
- kube-prometheus-stack

The AWS Load Balancer Controller is intentionally not included in the default base. Enable its example only after confirming the cluster provider is AWS, Terraform does not install the controller, and Terraform has created its IAM policy and EKS Pod Identity association.

Run `scripts/detect-cluster-provider.sh` with a configured kubeconfig before enabling cloud-specific resources. For GKE, AKS, and bare-metal clusters, do not enable the AWS controller. Configure the equivalent cloud-specific external-dns provider and identity outside this repository.

Cloud-specific values such as cluster names, regions, hosted-zone identifiers, workload identity bindings, managed identity assignments, and IAM role or Pod Identity configuration must come from Terraform or the cloud platform. Never commit credentials, tokens, certificates, passwords, or private keys.
