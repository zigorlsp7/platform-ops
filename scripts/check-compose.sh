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
local_env_example="$REPO_ROOT/docker/.env.ops.local.example"

if [ ! -f "$local_env_source" ]; then
  if [ -f "$local_env_example" ]; then
    local_env_source="$local_env_example"
  else
    echo "Missing required local ops env file: docker/.env.ops.local" >&2
    exit 1
  fi
fi

cp "$local_env_source" "$local_env_tmp"
cp "$REPO_ROOT/docker/.env.ops.prod" "$prod_env_tmp"

# Ensure external shell env does not override values from --env-file during validation.
compose_vars=(
  GRAFANA_ADMIN_USER
  GRAFANA_ADMIN_PASSWORD
  TOLGEE_INITIAL_USERNAME
  TOLGEE_INITIAL_PASSWORD
  TOLGEE_JWT_SECRET
  AWS_REGION
  OPENBAO_UNSEAL_AWS_ACCESS_KEY_ID
  OPENBAO_UNSEAL_AWS_SECRET_ACCESS_KEY
  UNLEASH_DB_PASSWORD
  UNLEASH_ADMIN_USERNAME
  UNLEASH_ADMIN_PASSWORD
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
set_key_if_missing_or_empty "$local_env_tmp" "GRAFANA_ADMIN_USER" "admin"
set_key_if_missing_or_empty "$local_env_tmp" "GRAFANA_ADMIN_PASSWORD" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$local_env_tmp" "TOLGEE_INITIAL_USERNAME" "platform_ops_admin"
set_key_if_missing_or_empty "$local_env_tmp" "TOLGEE_INITIAL_PASSWORD" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$local_env_tmp" "TOLGEE_JWT_SECRET" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$local_env_tmp" "UNLEASH_DB_PASSWORD" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$local_env_tmp" "UNLEASH_ADMIN_PASSWORD" "__placeholder_for_compose_validation__"

# Required keys for prod compose validation.
set_key_if_missing_or_empty "$prod_env_tmp" "GRAFANA_ADMIN_USER" "platform_ops_admin"
set_key_if_missing_or_empty "$prod_env_tmp" "GRAFANA_ADMIN_PASSWORD" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$prod_env_tmp" "TOLGEE_INITIAL_USERNAME" "platform_ops_admin"
set_key_if_missing_or_empty "$prod_env_tmp" "TOLGEE_INITIAL_PASSWORD" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$prod_env_tmp" "TOLGEE_JWT_SECRET" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$prod_env_tmp" "AWS_REGION" "eu-west-1"
set_key_if_missing_or_empty "$prod_env_tmp" "OPENBAO_UNSEAL_AWS_ACCESS_KEY_ID" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$prod_env_tmp" "OPENBAO_UNSEAL_AWS_SECRET_ACCESS_KEY" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$prod_env_tmp" "UNLEASH_DB_PASSWORD" "__placeholder_for_compose_validation__"
set_key_if_missing_or_empty "$prod_env_tmp" "UNLEASH_ADMIN_PASSWORD" "__placeholder_for_compose_validation__"

docker compose --env-file "$local_env_tmp" -f "$REPO_ROOT/docker/compose.ops.local.yml" config > "$local_tmp"
docker compose --env-file "$prod_env_tmp" -f "$REPO_ROOT/docker/compose.ops.prod.yml" config > "$prod_tmp"

caddyfile="$REPO_ROOT/docker/caddy/Caddyfile.ops.ingress.prod"
ingress_env="$(docker compose --env-file "$prod_env_tmp" -f "$REPO_ROOT/docker/compose.ops.prod.yml" config --format json \
  | jq -r '.services["central-ingress"].environment | keys[]')"

missing=()
while read -r placeholder; do
  [ -n "$placeholder" ] || continue
  if ! printf '%s\n' "$ingress_env" | grep -qx "$placeholder"; then
    missing+=("$placeholder")
  fi
done < <(grep -oE '\{\$[A-Z0-9_]+\}' "$caddyfile" | tr -d '{$}' | sort -u)

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Caddyfile placeholders not passed into the central-ingress container: ${missing[*]}" >&2
  echo "Add each to the environment block of central-ingress in docker/compose.ops.prod.yml." >&2
  echo "An unset placeholder becomes an empty site address, which Caddy refuses, taking every route down." >&2
  exit 1
fi

echo "Compose config render passed (local + prod), and every Caddyfile placeholder reaches the ingress."
