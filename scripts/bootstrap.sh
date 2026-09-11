#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.1.0}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REPO_URL="${REPO_URL:-https://github.com/pratik-khot/gitops-repo.git}"
VALUES_FILE="environments/${ENVIRONMENT}/applications.yaml"

case "${ENVIRONMENT}" in
  dev|staging|prod)
    ;;
  *)
    echo "ENVIRONMENT must be one of: dev, staging, prod" >&2
    exit 1
    ;;
esac

if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "Environment values file not found: ${VALUES_FILE}" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

kubectl config current-context

kubectl apply -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s

kubectl apply -f bootstrap/projects/platform-project.yaml -f bootstrap/projects/apps-project.yaml
kubectl apply -f bootstrap/argocd-root-application.yaml

kubectl -n argocd patch application/argocd-root --type merge --patch "{\"spec\":{\"sources\":[{\"repoURL\":\"${REPO_URL}\",\"targetRevision\":\"main\",\"path\":\"charts/argocd-application-inventory\",\"helm\":{\"valueFiles\":[\"\\$values/${VALUES_FILE}\"]}},{\"repoURL\":\"${REPO_URL}\",\"targetRevision\":\"main\",\"ref\":\"values\"}]}}"

echo "Argo CD bootstrap submitted for environment: ${ENVIRONMENT}"
echo "Initial Argo CD access: kubectl -n argocd port-forward svc/argocd-server 8080:443"
