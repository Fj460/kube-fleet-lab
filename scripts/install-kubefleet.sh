#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/.generated"
KUBECONFIG_FILE="$OUT_DIR/kubeconfig"

for command in kubectl helm curl; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

[[ -f "$KUBECONFIG_FILE" ]] || {
  echo "Missing $KUBECONFIG_FILE. Run ./scripts/apply-k0s.sh first." >&2
  exit 1
}

export KUBECONFIG="$KUBECONFIG_FILE"
KUBEFLEET_VERSION="${KUBEFLEET_VERSION:-0.3.2}"
HUB_PUBLIC_IP="$(terraform -chdir="$ROOT/terraform" output -raw hub_public_ip)"
JOIN_SCRIPT="$OUT_DIR/join-member-clusters.sh"

echo "Installing KubeFleet hub agent version $KUBEFLEET_VERSION..."
helm upgrade --install hub-agent \
  oci://ghcr.io/kubefleet-dev/kubefleet/charts/hub-agent \
  --version "$KUBEFLEET_VERSION" \
  --kube-context fleet-hub \
  --namespace fleet-system \
  --create-namespace \
  --set logFileMaxSize=100000

# Use the official upstream helper rather than duplicating its token/RBAC steps.
JOIN_URL="https://raw.githubusercontent.com/kubefleet-dev/kubefleet/main/hack/quickstart/join-member-clusters.sh"
curl --fail --location --silent --show-error "$JOIN_URL" --output "$JOIN_SCRIPT"
chmod 700 "$JOIN_SCRIPT"

echo "Joining member clusters to hub at https://${HUB_PUBLIC_IP}:6443 ..."
"$JOIN_SCRIPT" "$KUBEFLEET_VERSION" fleet-hub "https://${HUB_PUBLIC_IP}:6443/" member-1 member-2

echo
echo "Current member cluster status:"
kubectl --context fleet-hub get memberclusters
