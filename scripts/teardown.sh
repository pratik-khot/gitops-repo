#!/usr/bin/env bash
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.1.0}"
DELETE_TIMEOUT="${DELETE_TIMEOUT:-300s}"
ASSUME_YES=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ./scripts/teardown.sh [--dry-run] [--yes]

Deletes the Argo CD bootstrap resources and workloads managed by them.

Options:
  --dry-run  Print destructive commands without running them
  --yes      Skip the Kubernetes context confirmation
  -h, --help Show this help
EOF
}

while (($# > 0)); do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    --yes)
      ASSUME_YES=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

CURRENT_CONTEXT="$(kubectl config current-context)"
echo "Kubernetes context: ${CURRENT_CONTEXT}"
echo "This removes Argo CD and the workloads managed by this bootstrap."

if [[ "${ASSUME_YES}" == false && "${DRY_RUN}" == false ]]; then
  read -r -p "Type the Kubernetes context name to continue: " CONFIRMED_CONTEXT
  if [[ "${CONFIRMED_CONTEXT}" != "${CURRENT_CONTEXT}" ]]; then
    echo "Context confirmation did not match; nothing was deleted." >&2
    exit 1
  fi
fi

run() {
  if [[ "${DRY_RUN}" == true ]]; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}

run kubectl delete application central-gitops-bootstrap \
  --namespace argocd --ignore-not-found --wait=false
run kubectl delete applicationset cluster-inventories \
  --namespace argocd --ignore-not-found --wait=false
run kubectl delete applications \
  --namespace argocd --selector gitops.example.com/cluster \
  --ignore-not-found --wait=false

if [[ "${DRY_RUN}" == false ]] && kubectl api-resources --api-group=argoproj.io --no-headers 2>/dev/null | grep -q '^applications '; then
  if kubectl get applications --namespace argocd --selector gitops.example.com/cluster --output=name 2>/dev/null | grep -q .; then
    kubectl wait applications --namespace argocd \
      --selector gitops.example.com/cluster --for=delete --timeout="${DELETE_TIMEOUT}"
  fi

  if kubectl get application central-gitops-bootstrap --namespace argocd >/dev/null 2>&1; then
    kubectl wait application/central-gitops-bootstrap --namespace argocd \
      --for=delete --timeout="${DELETE_TIMEOUT}"
  fi
fi

run kubectl delete \
  --filename bootstrap/projects/platform-project.yaml \
  --filename bootstrap/projects/apps-project.yaml \
  --ignore-not-found
run kubectl delete --namespace argocd \
  --filename "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" \
  --ignore-not-found
run kubectl delete --filename bootstrap/argocd-install.yaml --ignore-not-found

if [[ "${DRY_RUN}" == true ]]; then
  echo "Dry run complete; nothing was deleted."
else
  echo "Argo CD bootstrap resources and managed workloads were deleted."
fi