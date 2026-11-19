
#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"
OUT_DIR="$ROOT/.generated"

CLUSTERS=(fleet-hub member-1 member-2)

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

# --------------------------------------------------
# 1. Check dependencies
# --------------------------------------------------

for command in terraform jq k0sctl kubectl; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

# --------------------------------------------------
# 2. Retrieve Terraform outputs
# --------------------------------------------------

echo "Retrieving Terraform outputs..."

if ! TF_OUTPUTS="$(terraform -chdir="$TF_DIR" output -json)"; then
  echo "ERROR: Failed to retrieve Terraform outputs." >&2
  exit 1
fi

HUB_PUBLIC_IP="$(
  jq -er '.cluster_public_ips.value["fleet-hub"] // error("Missing fleet-hub IP")' \
    <<< "$TF_OUTPUTS"
)"

MEMBER_1_PUBLIC_IP="$(
  jq -er '.cluster_public_ips.value["member-1"] // error("Missing member-1 IP")' \
    <<< "$TF_OUTPUTS"
)"

MEMBER_2_PUBLIC_IP="$(
  jq -er '.cluster_public_ips.value["member-2"] // error("Missing member-2 IP")' \
    <<< "$TF_OUTPUTS"
)"

# --------------------------------------------------
# 3. Export environment variables for k0sctl
# --------------------------------------------------

export HUB_PUBLIC_IP
export MEMBER_1_PUBLIC_IP
export MEMBER_2_PUBLIC_IP

export SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-$HOME/.ssh/kube-fleet-lab}"

if [[ ! -f "$SSH_PRIVATE_KEY" ]]; then
  echo "SSH private key not found: $SSH_PRIVATE_KEY" >&2
  exit 1
fi

echo
echo "Infrastructure configuration:"
echo "  Fleet Hub: $HUB_PUBLIC_IP"
echo "  Member 1:  $MEMBER_1_PUBLIC_IP"
echo "  Member 2:  $MEMBER_2_PUBLIC_IP"
echo "  SSH key:   $SSH_PRIVATE_KEY"
echo

# --------------------------------------------------
# 4. Validate k0sctl configurations
# --------------------------------------------------

for cluster in "${CLUSTERS[@]}"; do
  config="$ROOT/k0sctl/$cluster.yaml"

  if [[ ! -f "$config" ]]; then
    echo "Missing k0sctl configuration: $config" >&2
    exit 1
  fi
done

# --------------------------------------------------
# 5. Deploy clusters using k0sctl
# --------------------------------------------------

for cluster in "${CLUSTERS[@]}"; do
  echo
  echo "Applying $cluster..."

  k0sctl apply \
    --config "$ROOT/k0sctl/$cluster.yaml"
done

# --------------------------------------------------
# 6. Retrieve individual kubeconfigs
# --------------------------------------------------

for cluster in "${CLUSTERS[@]}"; do

  echo
  echo "Retrieving kubeconfig for $cluster..."

  cfg="$OUT_DIR/$cluster.kubeconfig"

  k0sctl kubeconfig \
    --config "$ROOT/k0sctl/$cluster.yaml" \
    > "$cfg"

  chmod 600 "$cfg"

  # Get existing context
  old_context="$(
    kubectl config get-contexts \
      --kubeconfig "$cfg" \
      -o name | sed -n '1p'
  )"

  if [[ -z "$old_context" ]]; then
    echo "Could not identify context in $cfg" >&2
    exit 1
  fi

  # Get existing user
  old_user="$(
    kubectl config view \
      --kubeconfig "$cfg" \
      -o json |
    jq -r --arg context "$old_context" \
      '.contexts[] | select(.name == $context) | .context.user // empty'
  )"

  if [[ -z "$old_user" ]]; then
    echo "Could not identify user in $cfg" >&2
    exit 1
  fi

  # Rename context
  if [[ "$old_context" != "$cluster" ]]; then
    kubectl config rename-context \
      "$old_context" "$cluster" \
      --kubeconfig "$cfg"
  fi

  # Rename user and update context references
  new_user="${cluster}-admin"

  kubectl config view --raw \
    --kubeconfig "$cfg" \
    -o json |
  jq --arg old "$old_user" --arg new "$new_user" '
    .users |= map(
      if .name == $old then .name = $new else . end
    ) |
    .contexts |= map(
      if .context.user == $old then .context.user = $new else . end
    )
  ' > "$cfg.tmp"

  mv "$cfg.tmp" "$cfg"
  chmod 600 "$cfg"

  echo "Context: $cluster | User: $new_user"

done

# --------------------------------------------------
# 7. Merge kubeconfigs
# --------------------------------------------------

KUBECONFIG_FILES=()

for cluster in "${CLUSTERS[@]}"; do
  KUBECONFIG_FILES+=("$OUT_DIR/$cluster.kubeconfig")
done

MERGED_KUBECONFIG="$OUT_DIR/kubeconfig"

KUBECONFIG="$(IFS=:; echo "${KUBECONFIG_FILES[*]}")" \
  kubectl config view --raw --flatten \
  > "$MERGED_KUBECONFIG"

chmod 600 "$MERGED_KUBECONFIG"

# --------------------------------------------------
# 8. Verify clusters
# --------------------------------------------------

echo
echo "Merged kubeconfig created at:"
echo "$MERGED_KUBECONFIG"
echo

for cluster in "${CLUSTERS[@]}"; do

  echo "Checking $cluster..."

  kubectl \
    --kubeconfig "$MERGED_KUBECONFIG" \
    --context "$cluster" \
    get nodes

done

echo
echo "All clusters successfully configured!"
