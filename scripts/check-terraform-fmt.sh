#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform is required for terraform fmt checks." >&2
  exit 1
fi

terraform -chdir="$REPO_ROOT/infra/terraform" fmt -check -recursive

echo "Terraform fmt check passed."
