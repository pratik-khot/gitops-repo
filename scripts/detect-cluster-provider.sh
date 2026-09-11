#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

provider_ids="$(kubectl get nodes -o jsonpath='{range .items[*]}{.spec.providerID}{"\n"}{end}')"
case "${provider_ids,,}" in
  *aws://*) echo "aws" ;;
  *gce://*) echo "gcp" ;;
  *azure://*) echo "azure" ;;
  *) echo "bare-metal" ;;
esac
