#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"

if [[ ! -d "$TF_DIR/.terraform" ]]; then
  echo "Terraform has not been initialized in $TF_DIR." >&2
  exit 1
fi

echo "This will DESTROY all Terraform-managed lab resources in DigitalOcean."
echo "Make sure you have saved any data you need."
read -r -p "Type DESTROY to continue: " answer
if [[ "$answer" != "DESTROY" ]]; then
  echo "Cancelled."
  exit 0
fi

terraform -chdir="$TF_DIR" destroy
rm -rf "$ROOT/.generated"
echo "Generated kubeconfigs removed. Confirm the Terraform destroy completed successfully in the output above."
