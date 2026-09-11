#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.1.0}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
REPO_URL="${REPO_URL:-https://github.com/pratik-khot/gitops-repo.git}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

kubectl apply -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s

kubectl apply -f bootstrap/projects/platform-project.yaml -f bootstrap/projects/apps-project.yaml
kubectl apply -f bootstrap/argocd-root-app.yaml

kubectl -n argocd patch application/argocd-root --type merge --patch "{\"spec\":{\"source\":{\"repoURL\":\"${REPO_URL}\",\"targetRevision\":\"main\",\"path\":\"clusters/${ENVIRONMENT}\"}}}"

echo "Argo CD bootstrap submitted for environment: ${ENVIRONMENT}"
