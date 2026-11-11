
#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"
OUT_DIR="$ROOT/.generated"

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

TF_OUTPUTS="$(terraform -chdir="$TF_DIR" output -json)"

HUB_PUBLIC_IP="$(
  jq -er '.hub_public_ip.value' <<< "$TF_OUTPUTS"
)"

MEMBER_1_PUBLIC_IP="$(
  jq -er '.member_public_ips.value["member-1"]' <<< "$TF_OUTPUTS"
)"

MEMBER_2_PUBLIC_IP="$(
  jq -er '.member_public_ips.value["member-2"]' <<< "$TF_OUTPUTS"
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

echo "Infrastructure configuration:"
echo "  Hub:      $HUB_PUBLIC_IP"
echo "  Member 1: $MEMBER_1_PUBLIC_IP"
echo "  Member 2: $MEMBER_2_PUBLIC_IP"
echo "  SSH key:  $SSH_PRIVATE_KEY"
echo

# --------------------------------------------------
# 4. Deploy clusters using k0sctl
# --------------------------------------------------

echo "Applying fleet hub..."

k0sctl apply --config "$ROOT/k0sctl/fleet-hub.yaml"

for member in member-1 member-2; do
  echo "Applying $member..."

  k0sctl apply \
    --config "$ROOT/k0sctl/$member.yaml"
done


# --------------------------------------------------
# 5. Retrieve individual kubeconfigs
# --------------------------------------------------

CLUSTERS=(fleet-hub member-1 member-2)

for cluster in "${CLUSTERS[@]}"; do

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
      -o name | head -n 1
  )"

  # Get existing user
  old_user="$(
    kubectl config view \
      --kubeconfig "$cfg" \
      -o json |
    jq -r '.contexts[] | select(.name == "'"$old_context"'") | .context.user'
  )"

  if [[ -z "$old_context" || -z "$old_user" || "$old_user" == "null" ]]; then
    echo "Could not identify context or user in $cfg" >&2
    exit 1
  fi

  # Rename context if necessary
  if [[ "$old_context" != "$cluster" ]]; then
    kubectl config rename-context \
      "$old_context" "$cluster" \
      --kubeconfig "$cfg"
  fi

# Rename user entry and update context references
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
# 6. Merge kubeconfigs
# --------------------------------------------------

KUBECONFIG_FILES=()

for cluster in "${CLUSTERS[@]}"; do
  KUBECONFIG_FILES+=("$OUT_DIR/$cluster.kubeconfig")
done

export KUBECONFIG
KUBECONFIG="$(IFS=:; echo "${KUBECONFIG_FILES[*]}")" \
  kubectl config view --raw --flatten \
  > "$OUT_DIR/kubeconfig"

chmod 600 "$OUT_DIR/kubeconfig"


# --------------------------------------------------
# 7. Verify clusters
# --------------------------------------------------

echo
echo "Merged kubeconfig created at:"
echo "$OUT_DIR/kubeconfig"
echo

for cluster in "${CLUSTERS[@]}"; do

  echo "Checking $cluster..."

  kubectl \
    --kubeconfig "$OUT_DIR/kubeconfig" \
    --context "$cluster" \
    get nodes

done

echo
echo "All clusters successfully configured!"
