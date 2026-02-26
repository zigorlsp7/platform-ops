#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_OPS_ENV_FILE="$REPO_ROOT/docker/.env.ops.local"
OPS_ENV_EXAMPLE_FILE="$REPO_ROOT/docker/.env.ops.local.example"
OPS_ENV_FILE="$DEFAULT_OPS_ENV_FILE"
OPS_COMPOSE_FILE="$REPO_ROOT/docker/compose.ops.local.yml"
OPENBAO_LOCAL_ADDR="http://localhost:8200"

if [ ! -f "$OPS_ENV_FILE" ]; then
  if [ -f "$OPS_ENV_EXAMPLE_FILE" ]; then
    cp "$OPS_ENV_EXAMPLE_FILE" "$OPS_ENV_FILE"
    chmod 600 "$OPS_ENV_FILE" || true
    echo "Created $OPS_ENV_FILE from $OPS_ENV_EXAMPLE_FILE."
    echo "Update placeholder values in $OPS_ENV_FILE when needed."
  else
    echo "Missing $OPS_ENV_FILE. Copy docker/.env.ops.local.example to docker/.env.ops.local and fill required values." >&2
    exit 1
  fi
fi

# Use .env.ops.local as the single local source of truth.
set -a
# shellcheck disable=SC1090
source "$OPS_ENV_FILE"
set +a

require_env() {
  local key="$1"
  local value=""
  if printenv "$key" >/dev/null; then
    value="$(printenv "$key")"
  fi
  if [ -z "$value" ]; then
    echo "$key is required in $OPS_ENV_FILE" >&2
    exit 1
  fi
}

prepare_openbao_volume_permissions() {
  local openbao_uid
  local openbao_gid

  set +e
  openbao_uid="$(docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" run --rm --no-deps --entrypoint sh openbao -lc 'id -u' 2>/dev/null | tr -d '\r' | tail -n1)"
  openbao_gid="$(docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" run --rm --no-deps --entrypoint sh openbao -lc 'id -g' 2>/dev/null | tr -d '\r' | tail -n1)"
  set -e

  if ! [[ "$openbao_uid" =~ ^[0-9]+$ ]]; then
    openbao_uid="100"
  fi

  if ! [[ "$openbao_gid" =~ ^[0-9]+$ ]]; then
    openbao_gid="1000"
  fi

  if [ "$openbao_uid" = "0" ]; then
    openbao_uid="100"
  fi

  if [ "$openbao_gid" = "0" ]; then
    openbao_gid="1000"
  fi

  echo "Preparing OpenBao data permissions for uid:gid ${openbao_uid}:${openbao_gid}"
  docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" run --rm --no-deps --user 0:0 --entrypoint sh openbao -lc "mkdir -p /openbao/data && chown -R ${openbao_uid}:${openbao_gid} /openbao/data && chmod -R u+rwX,g+rwX,o+rwX /openbao/data"
}

require_env "OPENBAO_KV_MOUNT"
require_env "OPS_SHARED_NETWORK"
network_name="$OPS_SHARED_NETWORK"

compose_ops() {
  docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" "$@"
}

docker network create "$network_name" >/dev/null 2>&1 || true
prepare_openbao_volume_permissions
compose_ops up -d

echo "Waiting for OpenBao to become reachable..."
i=1
openbao_code=""
while [ $i -le 60 ]; do
  openbao_code="$(curl -s -o /dev/null -w '%{http_code}' "$OPENBAO_LOCAL_ADDR/v1/sys/health" || true)"
  case "$openbao_code" in
    200|429|472|473|501|503)
      break
      ;;
  esac
  sleep 2
  i=$((i + 1))
done

if [ $i -gt 60 ]; then
  echo "OpenBao did not become reachable in time" >&2
  compose_ops logs --no-color --tail=120 openbao || true
  exit 1
fi

case "$openbao_code" in
  200|429|472|473)
    echo "OpenBao is ready (initialized + unsealed)."
    ;;
  501)
    echo "OpenBao is running but not initialized (prod-like behavior)." >&2
    echo >&2
    echo "Run once:" >&2
    echo "  docker compose --env-file $OPS_ENV_FILE -f $OPS_COMPOSE_FILE exec -T openbao bao operator init -key-shares=1 -key-threshold=1" >&2
    echo "  docker compose --env-file $OPS_ENV_FILE -f $OPS_COMPOSE_FILE exec -T openbao bao operator unseal <UNSEAL_KEY>" >&2
    echo "  docker compose --env-file $OPS_ENV_FILE -f $OPS_COMPOSE_FILE exec -T openbao bao login <ROOT_TOKEN>" >&2
    echo "  docker compose --env-file $OPS_ENV_FILE -f $OPS_COMPOSE_FILE exec -T openbao bao secrets enable -path=${OPENBAO_KV_MOUNT} kv-v2" >&2
    exit 1
    ;;
  503)
    echo "OpenBao is initialized but sealed." >&2
    echo >&2
    echo "Unseal it:" >&2
    echo "  docker compose --env-file $OPS_ENV_FILE -f $OPS_COMPOSE_FILE exec -T openbao bao operator unseal <UNSEAL_KEY>" >&2
    exit 1
    ;;
  *)
    echo "Unexpected OpenBao health status code: $openbao_code" >&2
    exit 1
    ;;
esac

echo "Ops stack started."
