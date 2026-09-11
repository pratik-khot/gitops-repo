# AWS Load Balancer Controller

The AWS Load Balancer Controller is enabled by default through `application.yaml`.

Terraform creates the IAM role, policy, and EKS Pod Identity association for the `kube-system/aws-load-balancer-controller` ServiceAccount. Helm creates and owns that ServiceAccount; Terraform must not create or manage it. The Pod Identity association must match the cluster, namespace, and ServiceAccount name exactly. Do not add an `eks.amazonaws.com/role-arn` annotation here because that annotation is for IRSA, not Pod Identity.

Each environment overlay must provide:

- EKS cluster name
- AWS region
- Terraform-created IAM role ARN
- Any required VPC, subnet, security group, and certificate integration values

The Helm chart creates the controller CRDs. The controller creates AWS Application Load Balancers for later Kubernetes Ingress resources using `ingressClassName: alb`. Do not add credentials, keys, tokens, or certificates to Git. ACM certificate ARNs are environment configuration for future application Ingress resources, not Kubernetes Secret values.
