#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OPS_ENV_FILE="${OPS_ENV_FILE:-$REPO_ROOT/docker/.env.ops.local}"
OPS_COMPOSE_FILE="${OPS_COMPOSE_FILE:-$REPO_ROOT/docker/compose.ops.local.yml}"
OPENBAO_LOCAL_ADDR="${OPENBAO_LOCAL_ADDR:-http://localhost:8200}"

read_env_var_from_file() {
  local file="$1"
  local key="$2"
  local line
  line="$(grep -E "^${key}=" "$file" | tail -n1 || true)"
  if [ -z "${line:-}" ]; then
    printf ''
    return
  fi
  printf '%s' "${line#*=}"
}

if [ ! -f "$OPS_ENV_FILE" ]; then
  echo "Missing $OPS_ENV_FILE. Create it and fill required values." >&2
  exit 1
fi

openbao_dev_root_token="$(read_env_var_from_file "$OPS_ENV_FILE" "OPENBAO_DEV_ROOT_TOKEN")"
openbao_kv_mount="$(read_env_var_from_file "$OPS_ENV_FILE" "OPENBAO_KV_MOUNT")"

if [ -z "${openbao_dev_root_token:-}" ]; then
  echo "OPENBAO_DEV_ROOT_TOKEN is required in $OPS_ENV_FILE" >&2
  exit 1
fi

if [ -z "${openbao_kv_mount:-}" ]; then
  echo "OPENBAO_KV_MOUNT is required in $OPS_ENV_FILE" >&2
  exit 1
fi

network_name="$(read_env_var_from_file "$OPS_ENV_FILE" "OPS_SHARED_NETWORK")"
if [ -z "$network_name" ]; then
  network_name="platform_ops_shared"
fi

docker network create "$network_name" >/dev/null 2>&1 || true
docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" up -d

echo "Waiting for OpenBao to become ready..."
i=1
while [ $i -le 60 ]; do
  if curl -fsS "$OPENBAO_LOCAL_ADDR/v1/sys/health" >/dev/null; then
    echo "OpenBao is ready"
    break
  fi
  sleep 2
  i=$((i + 1))
done

if [ $i -gt 60 ]; then
  echo "OpenBao did not become ready in time" >&2
  docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" logs --no-color --tail=120 openbao || true
  exit 1
fi

mount_path="${openbao_kv_mount%/}"
mounts_json="$(curl -fsS -H "X-Vault-Token: $openbao_dev_root_token" "$OPENBAO_LOCAL_ADDR/v1/sys/mounts")"
if ! MOUNT_PATH="$mount_path" node -e '
const fs = require("node:fs");
const mounts = JSON.parse(fs.readFileSync(0, "utf8"));
const mountPath = `${process.env.MOUNT_PATH}/`;
process.exit(Object.prototype.hasOwnProperty.call(mounts, mountPath) ? 0 : 1);
' <<<"$mounts_json"; then
  echo "OpenBao mount '$mount_path' does not exist. Creating kv-v2 mount..."
  curl -fsS \
    -H "X-Vault-Token: $openbao_dev_root_token" \
    -H "Content-Type: application/json" \
    -X POST \
    --data '{"type":"kv","options":{"version":"2"}}' \
    "$OPENBAO_LOCAL_ADDR/v1/sys/mounts/${mount_path}" >/dev/null
  echo "Created OpenBao mount '$mount_path' (kv-v2)."
fi

echo "Ops stack started."
