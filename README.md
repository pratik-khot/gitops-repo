# AWS EKS GitOps Repository

This repository demonstrates a practical organization-style GitOps setup for AWS EKS. Argo CD reads the desired Kubernetes state from Git, while Terraform owns the AWS infrastructure and identity prerequisites.

The repository is intentionally small enough to understand, but follows production habits: environment-specific configuration, separate platform and application projects, pinned versions, pull-request-based changes, and one owner for each resource.

It currently uses a root Argo CD Application with a Helm application inventory. ApplicationSets are a future option when the number of applications grows; they are not enabled here so the deployment flow remains easy to trace.

## Start here

There are four ideas to remember:

1. **Terraform creates the AWS foundation.** It creates EKS, networking, IAM, Route 53, ACM, and other AWS prerequisites.
2. **Argo CD deploys Kubernetes resources.** It watches this repository and keeps the cluster aligned with Git.
3. **The application inventory decides what is enabled.** The files under `environments/` turn platform controllers and workloads on or off for each environment.
4. **Kustomize describes workloads.** Files under `apps/` contain the Kubernetes manifests for an application.

For a first run, use this order:

```text
Terraform prerequisites
  -> EKS access
  -> ./scripts/bootstrap.sh
  -> Argo CD root Application
  -> generated child Applications
  -> platform controllers and workloads
```

Do not run the bootstrap script until the EKS cluster exists and the environment file has real cluster, region, and IAM values.

## Important terms

| Term | Meaning in this repository |
| --- | --- |
| Terraform | Creates AWS infrastructure and identity prerequisites. |
| Argo CD | Reconciles Kubernetes resources from Git. |
| Root Application | The first Argo CD Application created by the bootstrap script. |
| Application inventory | The Helm chart that generates child Argo CD Applications. |
| Child Application | One generated Argo CD Application for a controller or workload. |
| Helm | Installs upstream charts and renders the application inventory. |
| Kustomize | Builds application manifests from a base and environment overlay. |
| Environment | A separate dev, staging, or prod configuration and cluster. |

## Quick mental model

```text
Terraform
  AWS account, VPC, EKS, IAM, Route 53, ACM, Secrets Manager
        |
        v
Argo CD bootstrap
  installs Argo CD and creates the root Application
        |
        v
Helm application inventory
  creates one Argo CD Application for every enabled entry
        |
        +--> platform controllers from upstream Helm repositories
        +--> application workloads from apps/<name>/overlays/<environment>
```

## Architecture

```text
Route 53
  -> external-dns
  -> AWS Application Load Balancer
  -> AWS Load Balancer Controller
  -> Kubernetes Service
  -> application Pods

AWS Secrets Manager
  -> Secrets Store CSI Driver
  -> AWS provider
  -> Pod-mounted secret files
```

AWS ACM supplies TLS certificates for future ALB Ingress resources. `cert-manager` is intentionally not installed because ACM owns certificates. `ingress-nginx` is intentionally not installed because the AWS Load Balancer Controller owns AWS ALBs. Future application Ingress resources use `ingressClassName: alb`.

The normal change flow is: create a branch, change Git, render locally, open a pull request, review the diff, merge, and let Argo CD reconcile the approved revision. Production changes should use an explicit approval and a verified Kubernetes context.

## Repository layout

```text
bootstrap/
  argocd-root-application.yaml  Root Argo CD Application
  projects/                     Argo CD Projects and permissions
charts/argocd-application-inventory/
  Chart.yaml                    Helm chart for the application inventory
  values.yaml                   Shared platform inventory and defaults
  templates/                    Argo CD Application templates
environments/
  dev/applications.yaml         Dev overrides and enabled workloads
  staging/applications.yaml     Staging overrides and enabled workloads
  prod/applications.yaml        Production overrides and enabled workloads
apps/<app-name>/
  base/                         Shared workload manifests
  overlays/<environment>/       Environment-specific workload changes
scripts/bootstrap.sh            Initial Argo CD installation and registration
```

The `charts/argocd-application-inventory` chart is an inventory, not an application workload. It creates Argo CD `Application` objects. The actual workload manifests live under `apps/`.

The `templates/` directory contains Helm templates. The `_helpers.tpl` file contains reusable naming functions, such as the rule that names a generated Application `<environment>-<application>`. For example, the dev demo application becomes `dev-demo-app`.

## Ownership

Terraform owns the EKS cluster, VPC, subnets, networking, node groups, security groups, IAM roles and trust policies, IRSA or EKS Pod Identity, Route 53 hosted zones, ACM certificates, AWS Secrets Manager secrets, KMS permissions, PIA, and other AWS prerequisites.

GitOps owns Argo CD, Projects and Applications, platform Helm releases, Kubernetes namespaces, RBAC, network policies, application workloads, and `SecretProviderClass` resources. One resource must have one owner. Terraform must not manage Kubernetes resources also managed by Argo CD, and Argo CD must not recreate Terraform-owned AWS resources.

Service-account ownership is explicit: Terraform creates IAM roles and trust policies; Helm creates the controller ServiceAccounts and applies role ARN annotations. Terraform must not create those Kubernetes ServiceAccounts. If EKS Pod Identity is selected instead of IRSA, keep the same single-owner rule and configure the association in Terraform.

## Prerequisites and bootstrap

Required: `kubectl`, Kustomize or `kubectl kustomize`, Git, a Bash-compatible shell, access to the target EKS cluster, and repository access. Helm is optional for local chart inspection.

```bash
kubectl version
kubectl cluster-info
kubectl config current-context
kubectl auth can-i --list
```

The bootstrap identity must apply the upstream Argo CD manifest, create the `argocd` namespace and CRDs, and create/update Projects and Applications. Argo CD needs the resources permitted by the `platform` and `apps` AppProjects.

Dev is the default:

```bash
git clone https://github.com/pratik-khot/gitops-repo.git
cd gitops-repo
kubectl config use-context <dev-eks-context>
ENVIRONMENT=dev ./scripts/bootstrap.sh
```

For other clusters, select the matching context and be explicit:

```bash
ENVIRONMENT=staging ./scripts/bootstrap.sh
ENVIRONMENT=prod ./scripts/bootstrap.sh
```

Supported variables:

```bash
ARGOCD_VERSION=v3.1.0 ENVIRONMENT=dev ./scripts/bootstrap.sh
REPO_URL=https://github.com/<owner>/<repo>.git ENVIRONMENT=dev ./scripts/bootstrap.sh
```

The script installs Argo CD from the pinned upstream release, waits for the Applications CRD, applies `bootstrap/projects/*`, applies `bootstrap/argocd-root-application.yaml`, and selects `environments/<ENVIRONMENT>/applications.yaml` as the Helm values file. `bootstrap/argocd-install.yaml` is only the namespace/install note; it is not the full upstream installation manifest.

In practical terms, the bootstrap script performs these actions:

1. Checks that the selected environment file exists.
2. Installs the pinned Argo CD release.
3. Waits for the Argo CD `Application` CRD.
4. Applies the `platform` and `apps` Projects.
5. Creates the root Application.
6. Points the root Application at the selected environment inventory.

The script does not create the EKS cluster, IAM roles, Route 53 zones, ACM certificates, or application secrets. Those remain outside GitOps and must be prepared by Terraform or an approved AWS process.

Never use a dev context with `ENVIRONMENT=prod`. Verify after bootstrap:

```bash
kubectl -n argocd get pods -w
kubectl -n argocd get applications -o wide
kubectl -n argocd get appprojects
kubectl -n argocd get events --sort-by=.lastTimestamp
```

## Argo CD application hierarchy

`bootstrap/argocd-root-application.yaml` is the root Application. It renders `charts/argocd-application-inventory` with the selected environment values file. The chart creates one Argo CD Application per enabled entry:

```text
argocd-root
├── <environment>-argocd
├── <environment>-aws-load-balancer-controller
├── <environment>-external-dns
├── <environment>-metrics-server
└── <environment>-demo-app
```

The concrete child names are generated from the environment and inventory key. Helm-backed children source their upstream chart directly. Kustomize-backed children source this repository using the path in the environment values file. Disabled entries are not rendered.

For example, the dev environment currently enables `demo-app`:

```text
environments/dev/applications.yaml
  |
  v
dev-demo-app (generated Argo CD Application)
  |
  v
apps/demo-app/overlays/dev
```

This is the current App-of-Apps boundary: the root Application owns the generated child Applications, and each child owns one controller or workload. Do not create a second Argo CD Application for a resource already generated by this chart.

When this repository grows to many teams and services, an ApplicationSet can replace the inventory chart for workload generation. That migration should be deliberate and should not allow both systems to generate the same Application names.

Projects are applied before the root. Child sync waves are defined in `charts/argocd-application-inventory/values.yaml` and can be overridden per environment. Automated sync uses prune and self-heal where appropriate.

### external-dns

The AWS provider is enabled and Route 53 is the DNS target. Terraform owns hosted zones, IAM policy, and identity. Each overlay supplies role ARN, hosted-zone ID, and domain filter. external-dns manages Route 53 records; it does not create the zones.

### Secrets Store CSI Driver and AWS provider

The CSI Driver and AWS provider are separate Argo CD Helm children. The driver mounts AWS Secrets Manager values into Pod files through a `SecretProviderClass` and CSI volume. The AWS provider performs the AWS-specific retrieval. Terraform creates the Secrets Manager secrets, KMS permissions, IAM policy, and identity association. IAM policies should be narrowly scoped to approved secret ARNs.

The driver uses `syncSecret.enabled: false`. `secretObjects` is optional and should be added only when an application explicitly requires synchronization into a Kubernetes Secret. Mounted files are preferred and avoid creating a Kubernetes Secret unnecessarily.

`apps/secrets-store-csi-driver/base/secret-provider-class.example.yaml` is an example only. It is not referenced by Kustomize and is not deployed:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: example-secrets
  namespace: <application-namespace>
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: <aws-secrets-manager-secret-name>
        objectType: secretsmanager
```

To add one later, place a configured `SecretProviderClass` with the application overlay, reference it from that overlay, and mount the CSI volume from the Pod. Do not add production secret names or values to this repository.

### metrics-server and argo-rollouts

Metrics Server remains available for future HPA practice. Argo Rollouts remains installed for future progressive delivery. No Deployment, Rollout, or business workload is included.

### kube-prometheus-stack

Grafana remains `ClusterIP` and is not public by default. Retention is environment-specific. Persistence is currently an empty placeholder (`storageSpec: {}`); configure storage classes, capacity, and resources in overlays when required. Do not commit Grafana passwords or other secrets.

## Future ALB Ingress and ACM

ACM certificates are Terraform-owned and must exist in the same AWS region as the ALB. A future application Ingress should use `ingressClassName: alb` and an ACM ARN supplied through environment configuration:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: REPLACE_WITH_ACM_CERTIFICATE_ARN
spec:
  ingressClassName: alb
  rules:
    - host: REPLACE_WITH_ROUTE53_HOSTNAME
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app
                port:
                  number: 80
```

external-dns must have Route 53 permissions and a matching domain filter. Do not use cert-manager or Kubernetes TLS Secrets for ACM certificates.

## Adding applications

Keep applications under:

```text
apps/<app-name>/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/{dev,staging,prod}/
```

Use lowercase DNS-compatible names, pinned image tags/digests, requests and limits, health probes, replicas, least-privilege RBAC, and network policies. Add ConfigMaps for non-sensitive values, CSI-mounted secrets for sensitive files, and an ALB Ingress only when ready.

To add an application, create its base and environment overlays, then add an entry to the relevant `environments/<environment>/applications.yaml`. The entry must use `installer: kustomize`, project `apps`, and the overlay path. Set `enabled: false` until the workload is ready for that environment.

The usual application workflow is:

1. Create `apps/<app-name>/base/` with the shared Deployment, Service, and Kustomization.
2. Create one overlay for each environment you support.
3. Add the application to `environments/dev/applications.yaml` with `enabled: true`.
4. Render the overlay and inventory locally.
5. Open a pull request and review the generated Application and workload diff.
6. Merge the change and let Argo CD sync it.
7. Enable the same application in staging and production only after promotion approval.

Example inventory entry:

```yaml
apps:
  demo-app:
    enabled: true
    installer: kustomize
    path: apps/demo-app/overlays/dev
    project: apps
    destination:
      namespace: demo-app-dev
    argoSyncWave: "50"
    syncOptions:
      - CreateNamespace=true
```

Validate the workload and generated Application before promotion:

```bash
kubectl kustomize apps/<app-name>/overlays/dev
kubectl apply --dry-run=client -k apps/<app-name>/overlays/dev
helm template argocd-application-inventory charts/argocd-application-inventory --values environments/dev/applications.yaml
```

## Validation and health checks

```bash
helm template argocd-application-inventory charts/argocd-application-inventory --values environments/dev/applications.yaml
kubectl kustomize apps/demo-app/overlays/dev
kubectl kustomize apps/demo-app/overlays/staging
kubectl kustomize apps/demo-app/overlays/prod
git diff --check
ruby -e "require 'yaml'; Dir.glob('**/*.yaml').each { |file| YAML.load_stream(File.read(file)) }; puts 'Parsed YAML successfully'"
```

Verify paths and live health:

```bash
kubectl -n argocd get applications -o wide
kubectl -n argocd describe application dev-demo-app
kubectl -n kube-system get deployment aws-load-balancer-controller secrets-store-csi-driver
kubectl -n kube-system get daemonset secrets-store-csi-driver-provider-aws metrics-server
kubectl -n external-dns get pods
kubectl -n argo-rollouts get pods
kubectl -n monitoring get pods
kubectl get crd | grep -E 'secrets-store|rollout|prometheus|alertmanager'
kubectl get events -A --sort-by=.lastTimestamp
```

## Troubleshooting

- **Missing CRDs:** wait for Argo CD and CSI/controller CRDs; inspect child Application sync waves and logs.
- **Permission or identity errors:** verify Terraform-created IAM roles, trust policies, IRSA/Pod Identity, ServiceAccount annotations, and region.
- **Secrets not mounted:** verify the `SecretProviderClass`, AWS provider pod, CSI volume mount, secret ARN policy, KMS permissions, and Pod events.
- **Route 53 failure:** verify hosted-zone ID, domain filter, TXT ownership, external-dns role, and events.
- **ALB failure:** verify ALB controller role, subnet tags, security groups, VPC tags, ACM ARN/region, annotations, and controller events.
- **Namespace conflict:** ensure only Argo CD owns controller namespaces and Terraform does not recreate them.
- **Failed sync:** run `kubectl -n argocd describe application <name>`, inspect events, fix Git, and allow reconciliation to retry.
- **No application child:** confirm the app is enabled in `environments/<environment>/applications.yaml`, its source path exists, and the root Application is synced.

## Upgrades, rollback, and promotion

Argo CD is pinned by `ARGOCD_VERSION`; platform charts are pinned in their Applications. Review chart and CRD release notes, update one controller at a time, render all overlays, test dev, then promote staging and prod. Roll back by reverting Git to a known-good revision and verifying sync and health. Prune is enabled, so deleting desired resources can delete them from the cluster.

Production requires a verified context, rendered diff, IAM/DNS/ACM/network prerequisites, approval, and post-sync checks. Back up Git history and Terraform state separately for disaster recovery; recreate AWS prerequisites with Terraform before rerunning bootstrap.

## Required Terraform values per environment

For each dev, staging, and prod EKS environment, Terraform or approved external configuration must provide:

- EKS cluster name and AWS region
- AWS Load Balancer Controller IAM role ARN, trust policy, and policy permissions
- external-dns IAM role ARN, trust policy, Route 53 hosted-zone ID, and domain filter
- Secrets Store CSI AWS provider IAM role ARN, trust policy, approved Secrets Manager secret ARNs, and KMS permissions
- VPC/subnet/security-group configuration and required EKS/ALB tags
- ACM certificate ARN
- EKS Pod Identity or IRSA associations

These values appear as `REPLACE_WITH_*` placeholders in `environments/*/applications.yaml` and `charts/argocd-application-inventory/values.yaml`. Replace them through an approved configuration workflow without committing AWS credentials or secret values.

## Checklists and remaining gaps

- [ ] Terraform provisions EKS, networking, IAM/identity, Route 53, ACM, Secrets Manager, KMS, and ALB prerequisites.
- [ ] Bootstrap the correct environment and verify Argo Projects and Applications.
- [ ] Verify CSI driver/provider, AWS Load Balancer Controller, external-dns, metrics-server, rollouts, and monitoring health.
- [ ] Add application manifests and enable their generated child Applications only when ready.
- [ ] Configure SecretProviderClass and narrow IAM policies per application.
- [ ] Review production changes and retain rollback points.

Current placeholders: no production business workloads, environment AWS values, ACM ARN, CSI IAM role, and monitoring persistence. External Secrets Operator is intentionally not installed; cert-manager and ingress-nginx are intentionally not installed.
