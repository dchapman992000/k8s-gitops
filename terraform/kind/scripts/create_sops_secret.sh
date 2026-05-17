#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <kubeconfig> <context> <age_key_path>" >&2
  exit 2
fi

KUBECONFIG_PATH="$1"
KUBE_CONTEXT="$2"
AGE_KEY_PATH="$3"

if [ ! -f "$AGE_KEY_PATH" ]; then
  echo "Age key file not found: $AGE_KEY_PATH" >&2
  exit 3
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found in PATH" >&2
  exit 4
fi

# The Flux components manifest creates the namespace.
# This script only creates/updates the SOPS secret.
kubectl --kubeconfig="$KUBECONFIG_PATH" --context="$KUBE_CONTEXT" \
  create secret generic sops-age -n flux-system --from-file=age.agekey="$AGE_KEY_PATH" --dry-run=client -o yaml \
  | kubectl --kubeconfig="$KUBECONFIG_PATH" --context="$KUBE_CONTEXT" apply -f -

exit 0
