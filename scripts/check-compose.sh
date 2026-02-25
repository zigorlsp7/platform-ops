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
local_env_tmp="$(mktemp)"
prod_env_tmp="$(mktemp)"
trap 'rm -f "$local_tmp" "$prod_tmp" "$local_env_tmp" "$prod_env_tmp"' EXIT

local_env_source="$REPO_ROOT/docker/.env.ops.local"
if [ ! -f "$local_env_source" ]; then
  local_env_source="$REPO_ROOT/docker/.env.ops.local.example"
fi

if [ ! -f "$local_env_source" ]; then
  echo "Missing local ops env template (.env.ops.local or .env.ops.local.example)." >&2
  exit 1
fi

cp "$local_env_source" "$local_env_tmp"
cp "$REPO_ROOT/docker/.env.ops.prod" "$prod_env_tmp"

# Ensure external shell env does not override values from --env-file during validation.
compose_vars=(
  OPS_SHARED_NETWORK
  GRAFANA_ADMIN_USER
  GRAFANA_ADMIN_PASSWORD
  GRAFANA_USERS_ALLOW_SIGN_UP
  OPENBAO_DEV_ROOT_TOKEN
  OPENBAO_DEV_LISTEN_ADDRESS
  TOLGEE_AUTHENTICATION_ENABLED
  TOLGEE_AUTHENTICATION_REGISTRATIONS_ALLOWED
  TOLGEE_INITIAL_USERNAME
  TOLGEE_INITIAL_PASSWORD
  TOLGEE_JWT_SECRET
)
for key in "${compose_vars[@]}"; do
  unset "$key" || true
done

set_key_if_missing_or_empty() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  local current_line
  local current_value

  current_line="$(awk -F= -v k="$key" '$1 == k {line=$0} END {print line}' "$env_file")"
  current_value="${current_line#*=}"

  if [ -z "$current_line" ] || [ -z "$current_value" ]; then
    tmp_rewrite="$(mktemp)"
    awk -F= -v k="$key" -v v="$value" '
      BEGIN { replaced = 0 }
      $1 == k {
        if (!replaced) {
          print k "=" v
          replaced = 1
        }
        next
      }
      { print }
      END {
        if (!replaced) {
          print k "=" v
        }
      }
    ' "$env_file" > "$tmp_rewrite"
    mv "$tmp_rewrite" "$env_file"
  fi
}


# Required keys for local compose validation.
set_key_if_missing_or_empty "$local_env_tmp" "OPS_SHARED_NETWORK" "platform_ops_shared"
set_key_if_missing_or_empty "$local_env_tmp" "GRAFANA_ADMIN_USER" "admin"
set_key_if_missing_or_empty "$local_env_tmp" "GRAFANA_ADMIN_PASSWORD" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$local_env_tmp" "GRAFANA_USERS_ALLOW_SIGN_UP" "false"
set_key_if_missing_or_empty "$local_env_tmp" "OPENBAO_DEV_ROOT_TOKEN" "dev-only-root-token-change-me"
set_key_if_missing_or_empty "$local_env_tmp" "OPENBAO_DEV_LISTEN_ADDRESS" "0.0.0.0:8200"
set_key_if_missing_or_empty "$local_env_tmp" "TOLGEE_AUTHENTICATION_ENABLED" "true"
set_key_if_missing_or_empty "$local_env_tmp" "TOLGEE_AUTHENTICATION_REGISTRATIONS_ALLOWED" "false"
set_key_if_missing_or_empty "$local_env_tmp" "TOLGEE_INITIAL_USERNAME" "platform_ops_admin"
set_key_if_missing_or_empty "$local_env_tmp" "TOLGEE_INITIAL_PASSWORD" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$local_env_tmp" "TOLGEE_JWT_SECRET" "__placeholder_for_compose_validation__"

# Required keys for prod compose validation.
set_key_if_missing_or_empty "$prod_env_tmp" "OPS_SHARED_NETWORK" "platform_ops_shared"
set_key_if_missing_or_empty "$prod_env_tmp" "GRAFANA_ADMIN_USER" "platform_ops_admin"
set_key_if_missing_or_empty "$prod_env_tmp" "GRAFANA_ADMIN_PASSWORD" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$prod_env_tmp" "GRAFANA_USERS_ALLOW_SIGN_UP" "false"
set_key_if_missing_or_empty "$prod_env_tmp" "TOLGEE_AUTHENTICATION_ENABLED" "true"
set_key_if_missing_or_empty "$prod_env_tmp" "TOLGEE_AUTHENTICATION_REGISTRATIONS_ALLOWED" "false"
set_key_if_missing_or_empty "$prod_env_tmp" "TOLGEE_INITIAL_USERNAME" "platform_ops_admin"
set_key_if_missing_or_empty "$prod_env_tmp" "TOLGEE_INITIAL_PASSWORD" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$prod_env_tmp" "TOLGEE_JWT_SECRET" "__placeholder_for_compose_validation__"

docker compose --env-file "$local_env_tmp" -f "$REPO_ROOT/docker/compose.ops.local.yml" config > "$local_tmp"
docker compose --env-file "$prod_env_tmp" -f "$REPO_ROOT/docker/compose.ops.prod.yml" config > "$prod_tmp"

echo "Compose config render passed (local + prod)."
