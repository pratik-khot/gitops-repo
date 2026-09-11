# GitOps Repository

Argo CD and Kustomize definitions for the dev, staging, and production clusters.

## Repository layout

- `bootstrap/`: Argo CD installation, root application, and project definitions.
- `clusters/`: environment entrypoints that reconcile infrastructure and workloads.
- `platform/`: cluster add-ons and platform services.
- `apps/`: application workloads.
- `common/`: reusable namespaces, RBAC, and network policies.
- `projects/`: reserved for repository-wide project documentation or future definitions.
- `scripts/`: bootstrap helpers.

## Bootstrap

The default bootstrap targets the `dev` cluster entrypoint:

```bash
./scripts/bootstrap.sh
```

The script expects `kubectl` to point at the target cluster and installs the Argo CD server-side manifest before applying the root application. Change `ARGOCD_VERSION` or `ENVIRONMENT` when needed.

To render manifests without applying them:

```bash
kubectl kustomize platform/overlays/dev
kubectl kustomize apps/overlays/dev
```

Before promoting an environment, update the image references and environment-specific patches under the matching overlay.
