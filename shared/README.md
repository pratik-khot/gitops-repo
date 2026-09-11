# Shared Resources

This directory contains reusable Kubernetes resources that are shared across environments.

Ownership rules:

- Put resources here only when more than one environment or application uses them.
- Keep application-specific resources under `apps/<app-name>/base` or its environment overlay.
- Keep AWS infrastructure, IAM roles, Pod Identity associations, Route 53, ACM, and Secrets Manager resources in Terraform.
- Review namespace, network policy, and RBAC changes carefully because they can affect multiple workloads.

The child Kustomizations are entry points for shared namespaces, network policies, and RBAC. They are currently empty where no resource has a safe repository-wide default. Argo CD applications should reference a child Kustomization explicitly when a shared resource is ready to be deployed.