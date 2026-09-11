# AWS Load Balancer Controller

The AWS Load Balancer Controller is enabled by default through `application.yaml`.

This repository uses Option B: Terraform creates the IAM role and trust policy; Helm creates the `kube-system/aws-load-balancer-controller` ServiceAccount with the Terraform-provided IAM role ARN annotation. Terraform must not create or manage this ServiceAccount. If the cluster uses EKS Pod Identity instead of IRSA, adapt the Helm values and ownership contract so only one system manages the ServiceAccount.

Each environment overlay must provide:

- EKS cluster name
- AWS region
- Terraform-created IAM role ARN
- Any required VPC, subnet, security group, and certificate integration values

The Helm chart creates the controller CRDs. The controller creates AWS Application Load Balancers for later Kubernetes Ingress resources using `ingressClassName: alb`. Do not add credentials, keys, tokens, or certificates to Git. ACM certificate ARNs are environment configuration for future application Ingress resources, not Kubernetes Secret values.
