# AWS Load Balancer Controller

This controller is intentionally not included in `platform/base/kustomization.yaml`.

Enable it only when all of the following are true:

1. The target cluster is AWS EKS, confirmed from node/provider metadata.
2. Terraform does not install the controller or manage its Helm release.
3. Terraform has created the controller IAM policy and EKS Pod Identity association for the `kube-system/aws-load-balancer-controller` service account.
4. `application.yaml.example` is copied into an AWS-specific overlay and its cluster name and region are set from Terraform outputs.

Do not enable this manifest on GKE, AKS, or bare-metal clusters. Never add AWS credentials to this repository.
