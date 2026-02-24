#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for compose config validation." >&2
  exit 1
fi

local_tmp="$(mktemp)"
prod_tmp="$(mktemp)"
prod_env_tmp="$(mktemp)"
trap 'rm -f "$local_tmp" "$prod_tmp" "$prod_env_tmp"' EXIT

cp "$REPO_ROOT/docker/.env.ops.prod" "$prod_env_tmp"

# Prod runtime secrets are sourced from SSM during deployment, not from tracked env files.
# For compose rendering checks, inject non-sensitive placeholders when those keys are missing/empty.
required_prod_secret_keys=(
  GRAFANA_ADMIN_PASSWORD
  TOLGEE_INITIAL_PASSWORD
  TOLGEE_JWT_SECRET
)

for key in "${required_prod_secret_keys[@]}"; do
  current_line="$(awk -F= -v k="$key" '$1 == k {line=$0} END {print line}' "$prod_env_tmp")"
  current_value="${current_line#*=}"
  if [ -z "$current_line" ] || [ -z "$current_value" ]; then
    echo "${key}=__placeholder_for_compose_validation__" >> "$prod_env_tmp"
  fi
done

docker compose --env-file "$REPO_ROOT/docker/.env.ops.local" -f "$REPO_ROOT/docker/compose.ops.local.yml" config > "$local_tmp"
docker compose --env-file "$prod_env_tmp" -f "$REPO_ROOT/docker/compose.ops.prod.yml" config > "$prod_tmp"

echo "Compose config render passed (local + prod)."
