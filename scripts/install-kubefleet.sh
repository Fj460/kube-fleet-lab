#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"
OUT_DIR="$ROOT/.generated"
KUBECONFIG_FILE="$OUT_DIR/kubeconfig"

# --------------------------------------------------
# 1. Check dependencies
# --------------------------------------------------

for command in kubectl helm curl terraform jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

# --------------------------------------------------
# 2. Check kubeconfig
# --------------------------------------------------

[[ -f "$KUBECONFIG_FILE" ]] || {
  echo "Missing $KUBECONFIG_FILE. Run ./scripts/apply-k0s.sh first." >&2
  exit 1
}

export KUBECONFIG="$KUBECONFIG_FILE"

KUBEFLEET_VERSION="${KUBEFLEET_VERSION:-0.3.2}"

# --------------------------------------------------
# 3. Retrieve Fleet Hub IP
# --------------------------------------------------

echo "Retrieving Fleet Hub IP..."

TF_OUTPUTS="$(terraform -chdir="$TF_DIR" output -json)"

HUB_PUBLIC_IP="$(
  jq -er '.cluster_public_ips.value["fleet-hub"] // error("Missing fleet-hub IP")' \
    <<< "$TF_OUTPUTS"
)"

JOIN_SCRIPT="$OUT_DIR/join-member-clusters.sh"

echo "Fleet Hub IP: $HUB_PUBLIC_IP"
echo

# --------------------------------------------------
# 4. Install KubeFleet hub agent
# --------------------------------------------------

echo "Installing KubeFleet hub agent version $KUBEFLEET_VERSION..."

helm upgrade --install hub-agent \
  oci://ghcr.io/kubefleet-dev/kubefleet/charts/hub-agent \
  --version "$KUBEFLEET_VERSION" \
  --kube-context fleet-hub \
  --namespace fleet-system \
  --create-namespace \
  --set logFileMaxSize=100000

# --------------------------------------------------
# 5. Download official KubeFleet join helper
# --------------------------------------------------

JOIN_URL="https://raw.githubusercontent.com/kubefleet-dev/kubefleet/main/hack/quickstart/join-member-clusters.sh"

echo "Downloading KubeFleet join helper..."

curl --fail --location --silent --show-error \
  "$JOIN_URL" \
  --output "$JOIN_SCRIPT"

chmod 700 "$JOIN_SCRIPT"

# --------------------------------------------------
# 6. Join member clusters
# --------------------------------------------------

echo "Joining member clusters to hub at https://${HUB_PUBLIC_IP}:6443 ..."

"$JOIN_SCRIPT" \
  "$KUBEFLEET_VERSION" \
  fleet-hub \
  "https://${HUB_PUBLIC_IP}:6443/" \
  member-1 member-2

# --------------------------------------------------
# 7. Verify KubeFleet membership
# --------------------------------------------------

echo
echo "Current member cluster status:"

kubectl --context fleet-hub get memberclusters

echo
echo "KubeFleet installation completed!"
