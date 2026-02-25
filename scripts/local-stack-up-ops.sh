#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OPS_ENV_FILE="${OPS_ENV_FILE:-$REPO_ROOT/docker/.env.ops.local}"
OPS_COMPOSE_FILE="${OPS_COMPOSE_FILE:-$REPO_ROOT/docker/compose.ops.local.yml}"
OPENBAO_LOCAL_ADDR="${OPENBAO_LOCAL_ADDR:-http://localhost:8200}"

if [ ! -f "$OPS_ENV_FILE" ]; then
  echo "Missing $OPS_ENV_FILE. Copy docker/.env.ops.local.example to docker/.env.ops.local and fill required values." >&2
  exit 1
fi

# Use .env.ops.local as the single local source of truth.
set -a
# shellcheck disable=SC1090
source "$OPS_ENV_FILE"
set +a

require_env() {
  local key="$1"
  local value="${!key:-}"
  if [ -z "$value" ]; then
    echo "$key is required in $OPS_ENV_FILE" >&2
    exit 1
  fi
}

require_env "OPENBAO_DEV_ROOT_TOKEN"
require_env "OPENBAO_KV_MOUNT"

network_name="${OPS_SHARED_NETWORK:-platform_ops_shared}"

compose_ops() {
  docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" "$@"
}

docker network create "$network_name" >/dev/null 2>&1 || true
compose_ops up -d

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
  compose_ops logs --no-color --tail=120 openbao || true
  exit 1
fi

mount_path="${OPENBAO_KV_MOUNT%/}"
mounts_json="$(curl -fsS -H "X-Vault-Token: $OPENBAO_DEV_ROOT_TOKEN" "$OPENBAO_LOCAL_ADDR/v1/sys/mounts")"
if ! MOUNT_PATH="$mount_path" node -e '
const fs = require("node:fs");
const mounts = JSON.parse(fs.readFileSync(0, "utf8"));
const mountPath = `${process.env.MOUNT_PATH}/`;
process.exit(Object.prototype.hasOwnProperty.call(mounts, mountPath) ? 0 : 1);
' <<<"$mounts_json"; then
  echo "OpenBao mount '$mount_path' does not exist. Creating kv-v2 mount..."
  curl -fsS \
    -H "X-Vault-Token: $OPENBAO_DEV_ROOT_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST \
    --data '{"type":"kv","options":{"version":"2"}}' \
    "$OPENBAO_LOCAL_ADDR/v1/sys/mounts/${mount_path}" >/dev/null
  echo "Created OpenBao mount '$mount_path' (kv-v2)."
fi

echo "Ops stack started."
