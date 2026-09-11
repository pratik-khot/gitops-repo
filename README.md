# GitOps Repository

This repository manages Kubernetes resources with GitOps. Argo CD continuously compares the desired state in Git with the live cluster and reconciles drift. Kustomize renders shared bases and environment overlays. Argo CD Applications install pinned upstream Helm charts for platform controllers.

No business application workload, secret, credential, token, password, certificate, or cloud key is committed here. Application scaffolding is intentionally empty for the service owners who will add workloads later.

## Purpose and architecture

The deployment flow is:

```text
Terraform and cloud infrastructure
  -> Kubernetes cluster and cloud prerequisites
  -> Argo CD installation
  -> argocd-root Application
  -> environment parent Applications
  -> platform controller child Applications
  -> application child Applications
```

Repository structure:

```text
bootstrap/
├── argocd-install.yaml
├── argocd-root-app.yaml
├── projects/
│   ├── platform-project.yaml
│   └── apps-project.yaml
└── applications/
    ├── platform-app.yaml       # clearly marked template
    └── apps-app.yaml           # clearly marked template
clusters/
├── dev/
├── staging/
└── prod/
platform/
├── base/
└── overlays/
    ├── dev/
    ├── staging/
    └── prod/
apps/
├── kustomization.yaml
└── <app-name>/
    ├── base/
    └── overlays/
        ├── dev/
        ├── staging/
        └── prod/
common/
├── namespaces/
├── rbac/
└── network-policies/
scripts/
└── bootstrap.sh
```

`clusters/dev`, `clusters/staging`, and `clusters/prod` each contain two explicit parent Applications. The platform parent renders `platform/overlays/<environment>`. The apps parent renders `apps`, which is currently an empty Kustomization. Future application child Applications are added explicitly to the apps Kustomization; no ApplicationSet is used.

## Ownership boundary

Terraform in another repository owns cloud and cluster prerequisites:

- VPCs, networking, subnets, routing, and security groups
- Kubernetes cluster creation and node pools
- IAM, IRSA, EKS Pod Identity, GKE Workload Identity, and Azure managed identity
- DNS zones and cloud load balancer prerequisites
- PIA and other external infrastructure
- Managed Kubernetes add-ons such as EKS EBS CSI

This repository owns:

- Argo CD and its bootstrap entrypoints
- Argo CD Projects
- Argo CD Applications and the App of Apps hierarchy
- Kubernetes platform controllers
- Kubernetes namespaces, RBAC, and network policies
- Application workloads added under `apps/<app-name>/`

One resource must have one owner. Do not manage the same cluster, add-on, IAM association, DNS record, load balancer, namespace, or other resource from both Terraform and Argo CD. Confirm ownership before adding any resource.

## Prerequisites and permissions

Required tools:

- `kubectl`
- Kustomize or `kubectl kustomize`
- Git
- Bash-compatible shell for `scripts/bootstrap.sh`
- Access to the target Kubernetes cluster
- Access to this Git repository

Helm is optional and is useful for local chart inspection; Argo CD installs the configured charts.

Verify the client and target cluster:

```bash
kubectl version
kubectl cluster-info
kubectl config current-context
kubectl auth can-i --list
```

The bootstrap identity must be able to apply the upstream Argo CD manifest, create the `argocd` namespace and Argo CD CRDs, and create/update the Projects and root Application. Argo CD must be allowed to reconcile the resources in its installation and the resources permitted by the `platform` and `apps` AppProjects. Production access should be restricted to approved operators and should use the least privilege compatible with the platform design.

## Bootstrap

Dev is the default environment. Select the cluster context before running the script:

```bash
git clone https://github.com/pratik-khot/gitops-repo.git
cd gitops-repo
kubectl config use-context <target-context>
kubectl version
kubectl cluster-info
kubectl config current-context
kubectl auth can-i --list
ENVIRONMENT=dev ./scripts/bootstrap.sh
```

For staging or production, select the correct cluster context and make the environment explicit:

```bash
ENVIRONMENT=staging ./scripts/bootstrap.sh
ENVIRONMENT=prod ./scripts/bootstrap.sh
```

The script supports:

```bash
ARGOCD_VERSION=v3.1.0 ENVIRONMENT=dev ./scripts/bootstrap.sh
REPO_URL=https://github.com/<owner>/<repo>.git ENVIRONMENT=dev ./scripts/bootstrap.sh
```

The script:

1. Installs Argo CD from the upstream manifest for `ARGOCD_VERSION`.
2. Waits for the Applications CRD to become established.
3. Applies `bootstrap/projects/platform-project.yaml` and `bootstrap/projects/apps-project.yaml`.
4. Applies `bootstrap/argocd-root-app.yaml`.
5. Patches `argocd-root` with `REPO_URL` and `clusters/<ENVIRONMENT>`.

`bootstrap/argocd-install.yaml` creates the `argocd` namespace and an installation note. It is not a vendored Argo CD installation manifest; the script downloads the upstream release manifest. After bootstrapping, wait for pods and inspect the hierarchy:

```bash
kubectl -n argocd get pods -w
kubectl -n argocd get applications -o wide
kubectl -n argocd get appprojects
kubectl -n argocd get events --sort-by=.lastTimestamp
```

Do not use a dev context with `ENVIRONMENT=prod`. Review the context, repository URL, branch, and environment path before production bootstrap.

## App of Apps

This repository uses explicit App of Apps rather than ApplicationSets. An App of Apps is a parent Argo CD Application whose source contains child Argo CD Application manifests. The root Application manages the selected environment directory; that directory contains the platform and apps parent Applications; each parent then manages its child Applications.

The intended hierarchy is:

```text
argocd-root
├── dev-platform
├── dev-apps
├── staging-platform
├── staging-apps
├── prod-platform
└── prod-apps
```

Only the selected environment is managed by the root Application at a time. The other environment manifests remain in Git and are selected by a deliberate bootstrap choice.

The conceptual flow is:

```text
root Application
├── platform Application
│   ├── ingress-nginx Application
│   ├── cert-manager Application
│   ├── external-dns Application
│   ├── external-secrets Application
│   ├── metrics-server Application
│   ├── argo-rollouts Application
│   └── kube-prometheus-stack Application
└── apps Application
    └── future application child Applications
```

- The root Application is `bootstrap/argocd-root-app.yaml` and selects `clusters/<environment>`.
- Environment parent Applications are explicit files in `clusters/dev`, `clusters/staging`, and `clusters/prod`.
- Platform child Applications are under `platform/base/<controller>/application.yaml` and are rendered by `platform/overlays/<environment>`.
- The apps parent is the environment `*-apps` Application and currently renders the empty `apps/kustomization.yaml`.
- Future app child Applications must be explicit manifests listed by the apps Kustomization and must point to `apps/<app-name>/overlays/<environment>`.

App of Apps is useful when the hierarchy, ownership, sync status, and ordering should be visible as explicit Argo CD Applications. It avoids generator behavior and makes production application membership reviewable. Its costs are more manifests, explicit maintenance for every environment, and a higher risk of circular references if a child points back to its parent. A child must never manage the path that creates its parent.

Sync waves control ordering. The root is the bootstrap entrypoint; environment platform parents use wave `10`, apps parents use wave `20`, platform child controllers use waves `10`, `20`, or `30`, and application child Applications should use a later wave such as `40`. Projects are applied by the bootstrap script before the root Application. Do not create a cycle such as root -> platform -> root or apps -> parent apps.

## Platform and application parents

Each environment explicitly references both parents:

- `<environment>-platform` uses project `platform` and source `platform/overlays/<environment>`.
- `<environment>-apps` uses project `apps` and source `apps`.

Both use automated sync with `prune: true` and `selfHeal: true`. `CreateNamespace=true` is used for the Argo CD destination where appropriate. Platform controller Applications use `CreateNamespace=true` only for controller namespaces that they own. The metrics-server Application targets the existing `kube-system` namespace.

There are no real application workloads. The apps parent is intentionally healthy but empty until an application child Application is added.

## Argo CD Projects

An AppProject restricts source repositories, destination clusters, destination namespaces, cluster-scoped resources, and namespace-scoped resources.

### `platform`

Defined in `bootstrap/projects/platform-project.yaml`. It allows the repository `https://github.com/pratik-khot/gitops-repo.git`, the in-cluster destination, all namespaces, and all cluster- and namespace-scoped resources. It is intended for platform administrators because controller installation often includes CRDs and cluster-scoped resources.

### `apps`

Defined in `bootstrap/projects/apps-project.yaml`. It allows the same repository and in-cluster destination. It permits the `Namespace` cluster resource and all namespace-scoped resources. It is intended for application owners operating within their assigned namespaces.

### `default`

No `default` AppProject manifest exists here; `default` is Argo CD's built-in project. The root Application uses it because Projects are applied before the root and the root must bootstrap the hierarchy. Production workload Applications should use `apps`, not `default`, unless an explicitly approved exception exists. A future hardening change can create a restricted bootstrap project for the root and environment parents.

## Platform controllers

The platform base contains explicit Argo CD Applications for these pinned Helm charts:

| Controller | Purpose | Namespace | Chart version | Wave | Application manifest |
| --- | --- | --- | --- | --- | --- |
| ingress-nginx | Kubernetes Ingress controller | `ingress-nginx` | `ingress-nginx` `4.12.0` | `10` | `platform/base/ingress-nginx/application.yaml` |
| cert-manager | Certificate issuance and renewal | `cert-manager` | `cert-manager` `v1.16.5` | `10` | `platform/base/cert-manager/application.yaml` |
| external-dns | Publishes Kubernetes DNS records | `external-dns` | `external-dns` `1.15.0` | `20` | `platform/base/external-dns/application.yaml` |
| external-secrets | Syncs approved external secrets | `external-secrets` | `external-secrets` `0.10.7` | `20` | `platform/base/external-secrets/application.yaml` |
| metrics-server | Serves Kubernetes resource metrics | `kube-system` | `metrics-server` `3.12.1` | `20` | `platform/base/metrics-server/application.yaml` |
| argo-rollouts | Progressive delivery controller | `argo-rollouts` | `argo-rollouts` `2.37.0` | `20` | `platform/base/argo-rollouts/application.yaml` |
| kube-prometheus-stack | Prometheus, Alertmanager, Grafana, and exporters | `monitoring` | `kube-prometheus-stack` `65.8.1` | `30` | `platform/base/kube-prometheus-stack/application.yaml` |

The chart repositories and Helm release names are in those Application manifests. Common configuration is in `platform/base`; environment-specific replica and retention values are in `platform/overlays/dev`, `staging`, and `prod`.

The load balancer controller is not enabled. `platform/base/aws-load-balancer-controller/application.yaml.example` is a clearly marked placeholder and is not referenced by `platform/base/kustomization.yaml`. Do not claim it is installed.

Health checks:

```bash
kubectl -n argocd get applications
kubectl -n argocd describe application dev-platform
kubectl -n ingress-nginx get pods,svc
kubectl -n cert-manager get pods
kubectl -n external-dns get pods
kubectl -n external-secrets get pods
kubectl -n kube-system get deployment metrics-server
kubectl -n argo-rollouts get pods
kubectl -n monitoring get pods
kubectl get crd
```

Terraform owns cloud prerequisites and identity bindings. Argo CD owns the Helm releases. EKS managed add-ons such as EBS CSI remain Terraform-owned and are intentionally absent.

## Load balancer options

Run `./scripts/detect-cluster-provider.sh` to report `aws`, `gcp`, `azure`, or `bare-metal` from node provider IDs. The script reports the provider only; it does not automatically install anything.

- **AWS/EKS:** Enable the AWS Load Balancer Controller only when Terraform does not manage it. Terraform must create the required IAM permissions and IRSA or EKS Pod Identity association for `kube-system/aws-load-balancer-controller`. Configure cluster name and region from Terraform. Subnets, security groups, certificates, and hosted zones are external prerequisites. Never store AWS keys in Git.
- **GKE:** Prefer native GKE load balancing where appropriate. Use Workload Identity and the required Service or Ingress annotations. Do not enable the AWS controller.
- **Azure/AKS:** Use the supported Azure load balancer or Application Gateway integration with managed identity or workload identity. Configure Azure resources outside GitOps. Do not enable the AWS controller.
- **Bare metal:** Add MetalLB only when required and after reviewing address pools, L2/BGP, and network prerequisites. Do not install a provider-specific controller when the provider is unknown or Terraform already manages it.

Provider-specific external-dns values, hosted-zone identifiers, cloud identity, TLS certificate sources, and load balancer configuration must be supplied outside this repository or in a reviewed provider-specific overlay without credentials.

## Adding an application

Create one workload directory:

```text
apps/<app-name>/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

Use a lowercase DNS-compatible app name. Put Deployment and Service resources in `base`. Add Ingress only when the platform integration is configured. Use ConfigMaps for non-sensitive values and External Secrets for sensitive values. Define resource requests and limits, health probes, replicas, pinned image tags or digests, least-privilege RBAC, and network policies.

For App of Apps, create an explicit child Application manifest for each enabled environment under the application overlay, then add that manifest to `apps/kustomization.yaml`. Keep the child Application manifest separate from the workload Kustomization used by the child Application, so the child does not recursively manage itself. The child Application must use project `apps`, target the app namespace, and use source path `apps/<app-name>/overlays/<environment>`.

To enable dev, staging, or prod, add the corresponding child Application manifest and reference it from `apps/kustomization.yaml`. Validate the overlay before pushing:

```bash
kubectl kustomize apps/<app-name>/overlays/dev
kubectl apply --dry-run=client -k apps/<app-name>/overlays/dev
```

Promote dev -> staging -> prod only after review, rendered-manifest checks, and health verification in the previous environment. No sample business application is included in this repository.

## Secrets, identity, and security

- Never commit secrets, passwords, tokens, certificates, private keys, or cloud credentials.
- Use External Secrets with an approved secret manager. Add `SecretStore` and `ExternalSecret` resources only after the provider identity and permissions are configured externally.
- Use IRSA, EKS Pod Identity, GKE Workload Identity, Azure managed identity, or another approved workload identity mechanism instead of static cloud credentials.
- Use cert-manager with approved Issuers or externally managed certificates. Keep certificate authorities, DNS challenge credentials, and private keys outside Git.
- Use least-privilege AppProjects, ServiceAccounts, Roles, and RoleBindings.
- Use namespace isolation and network policies.
- Pin container images and Helm chart versions; never use `latest`.
- Require production review for changes to identity, ingress, DNS, RBAC, network policy, pruning, or controller versions.

## Validation and health checks

Run the requested local validation commands:

```bash
kubectl kustomize platform/overlays/dev
kubectl kustomize platform/overlays/staging
kubectl kustomize platform/overlays/prod
kubectl kustomize apps
git diff --check
```

Validate YAML when Ruby is available:

```bash
ruby -e "require 'yaml'; Dir.glob('**/*.yaml').each { |file| YAML.load_stream(File.read(file)) }; puts 'Parsed YAML successfully'"
```

Verify every Application source path exists:

```bash
Test-Path bootstrap/argocd-root-app.yaml
Test-Path clusters/dev
Test-Path clusters/staging
Test-Path clusters/prod
Test-Path platform/overlays/dev
Test-Path platform/overlays/staging
Test-Path platform/overlays/prod
Test-Path apps
```

Inspect Argo CD Applications, Projects, sync state, events, and controller pods:

```bash
kubectl -n argocd get applications -o wide
kubectl -n argocd get appprojects
kubectl -n argocd describe application argocd-root
kubectl -n argocd describe application dev-platform
kubectl -n argocd describe application dev-apps
kubectl -n argocd get events --sort-by=.lastTimestamp
kubectl get events -A --sort-by=.lastTimestamp
kubectl get pods -A
kubectl get crd
```

## Troubleshooting

| Problem | Checks |
| --- | --- |
| Bootstrap failure | Check Bash, `kubectl`, context, upstream URL access, permissions, Argo CD pods, and events. |
| Missing CRD | Wait for Argo CD and controller CRDs; inspect controller logs and sync waves. |
| Invalid repository path | Verify branch `main`, repository URL, and every `spec.source.path`. |
| Failed Kustomize render | Run the relevant `kubectl kustomize` command and check relative resources and patch targets. |
| Namespace conflict | Confirm whether Terraform or another Application owns the namespace; keep one owner. |
| Permission error | Check the bootstrap identity, Argo CD service account, AppProject destinations, and resource allowlists. |
| Cloud identity error | Verify Terraform-created IAM/Pod Identity, Workload Identity, managed identity, trust policy, and service account name. |
| DNS failure | Check external-dns provider values, zone permissions, domain filters, and Kubernetes events. |
| Certificate failure | Check cert-manager Issuer status, DNS challenge identity, DNS records, and events. |
| Load balancer failure | Confirm provider, subnets, security groups, annotations, certificates, controller ownership, and cloud events. |
| Failed Argo sync | Run `kubectl -n argocd describe application <name>`, inspect sync errors/events, fix Git, and allow reconciliation to retry. |
| Apps not appearing | Confirm the child Application is listed in `apps/kustomization.yaml`, its source path exists, and its project is `apps`. |
| Circular reference | Ensure parent Applications manage child Application manifests, while child Applications manage only workload manifests. |

## Upgrades, rollback, and promotion

Argo CD is pinned by `ARGOCD_VERSION` in `scripts/bootstrap.sh`. Upgrade it deliberately after reviewing upstream release notes and CRD compatibility. Upgrade a platform chart by changing its pinned `targetRevision`, rendering all overlays, testing dev, then promoting to staging and prod.

For a failed sync, inspect status and events first. Fix the Git change and let automated reconciliation retry, or pause automation through an approved Argo CD change process. Pruning is enabled, so removing a desired resource can delete it from the cluster. Roll back by reverting Git to the last known-good revision, then verify sync and health.

Production promotion requires a verified production context, reviewed diff, rendered manifests, cloud prerequisite verification, explicit approval, and post-sync controller/workload checks.

## Operational checklists

### First installation

- [ ] Terraform created the cluster and external prerequisites.
- [ ] Correct cluster context and permissions are verified.
- [ ] `ENVIRONMENT` is explicit for non-dev clusters.
- [ ] Argo CD pods and CRDs become ready.
- [ ] Projects, root, environment parents, and platform children are healthy.

### Add a platform controller

- [ ] Confirm Terraform does not own the resource.
- [ ] Add a pinned Argo CD Application under `platform/base`.
- [ ] Add it to the base Kustomization.
- [ ] Choose a sync wave after reviewing CRD dependencies.
- [ ] Add only non-secret environment configuration in overlays.
- [ ] Configure cloud identity externally.
- [ ] Render all platform overlays and review the diff.

### Add an application

- [ ] Create `apps/<app-name>/base` and the required overlays.
- [ ] Add the explicit child Application for each enabled environment.
- [ ] List child Application manifests in `apps/kustomization.yaml`.
- [ ] Add probes, requests, limits, RBAC, policies, and pinned images.
- [ ] Keep secrets and identity outside Git.
- [ ] Validate and promote through dev, staging, and prod.

### Production promotion

- [ ] Verify `kubectl config current-context`.
- [ ] Review the Git diff and rendered manifests.
- [ ] Confirm identity, DNS, ingress, certificates, and load balancer prerequisites.
- [ ] Obtain production approval.
- [ ] Verify sync, controller health, events, and probes.

### Credential rotation

- [ ] Rotate the value only in the approved external secret manager.
- [ ] Update identity or SecretStore configuration if needed.
- [ ] Confirm no secret entered Git history.
- [ ] Verify ExternalSecret and dependent workload health.

### Disaster recovery

- [ ] Back up this Git repository and Terraform state separately.
- [ ] Recreate cloud prerequisites and the cluster with Terraform.
- [ ] Select the correct context and run the bootstrap script.
- [ ] Verify Projects, Applications, controllers, identity, DNS, certificates, and workloads.

## Current placeholders and implementation gaps

- No business application workloads or child application manifests exist.
- `apps/kustomization.yaml` is intentionally empty, so the three apps parents currently manage no children.
- `bootstrap/applications/platform-app.yaml` and `apps-app.yaml` are clearly marked templates; the concrete parent Applications are in each `clusters/<environment>` directory.
- `common/namespaces`, `common/rbac`, and `common/network-policies` contain empty Kustomize scaffolding.
- The AWS Load Balancer Controller is disabled and remains an example only.
- `external-dns` currently selects the AWS provider in the shared base. GKE, Azure, and bare-metal clusters need provider-specific configuration before use.
- `scripts/detect-cluster-provider.sh` reports a provider but does not select or install a controller.
- The root and environment parent Applications use the built-in `default` project for bootstrap; production hardening should introduce a restricted bootstrap project.
- `scripts/bootstrap.sh` waits for the Applications CRD but does not wait for all Argo CD pods or Application health; perform the documented checks manually.
