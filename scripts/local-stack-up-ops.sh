#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_OPS_ENV_FILE="$REPO_ROOT/docker/.env.ops.local"
DEFAULT_OPS_ENV_EXAMPLE_FILE="$REPO_ROOT/docker/.env.ops.local.example"
OPS_ENV_FILE="$DEFAULT_OPS_ENV_FILE"
OPS_COMPOSE_FILE="$REPO_ROOT/docker/compose.ops.local.yml"
OPENBAO_LOCAL_ADDR="http://127.0.0.1:8200"
OPS_SHARED_NETWORK="platform_ops_shared"

OPENBAO_HEALTH_CODE=""

if [ ! -f "$OPS_ENV_FILE" ]; then
  if [ ! -f "$DEFAULT_OPS_ENV_EXAMPLE_FILE" ]; then
    echo "Missing required local env file: $OPS_ENV_FILE" >&2
    echo "Also missing example env file: $DEFAULT_OPS_ENV_EXAMPLE_FILE" >&2
    exit 1
  fi
  cp "$DEFAULT_OPS_ENV_EXAMPLE_FILE" "$OPS_ENV_FILE"
  echo "Created $OPS_ENV_FILE from $DEFAULT_OPS_ENV_EXAMPLE_FILE"
fi

for cmd in docker curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

compose_run_supports_no_build="false"
if docker compose run --help 2>/dev/null | grep -q -- '--no-build'; then
  compose_run_supports_no_build="true"
fi

# Use .env.ops.local as the local source of truth.
set -a
# shellcheck disable=SC1090
source "$OPS_ENV_FILE"
set +a

is_placeholder_value() {
  local value="$1"
  case "$value" in
    ""|CHANGE_ME*|SET_FROM_*) return 0 ;;
    *) return 1 ;;
  esac
}

require_non_empty_env_value() {
  local key="$1"
  local value="${!key:-}"
  if [ -z "$value" ]; then
    echo "$key is required in $OPS_ENV_FILE." >&2
    exit 1
  fi
}

require_non_placeholder_env_value() {
  local key="$1"
  local value="${!key:-}"
  if is_placeholder_value "$value"; then
    echo "$key in $OPS_ENV_FILE is not set. Provide a concrete local value." >&2
    exit 1
  fi
}

require_min_length_env_value() {
  local key="$1"
  local min_length="$2"
  local value="${!key:-}"

  if [ "${#value}" -lt "$min_length" ]; then
    echo "$key in $OPS_ENV_FILE is too short (${#value}). Minimum length is ${min_length}." >&2
    exit 1
  fi
}

compose_ops() {
  docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" "$@"
}

prepare_openbao_volume_permissions() {
  local openbao_uid
  local openbao_gid

  set +e
  if [ "$compose_run_supports_no_build" = "true" ]; then
    openbao_uid="$(docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" run --rm --no-deps --no-build --entrypoint sh openbao -lc 'id -u' 2>/dev/null | tr -d '\r' | tail -n1)"
    openbao_gid="$(docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" run --rm --no-deps --no-build --entrypoint sh openbao -lc 'id -g' 2>/dev/null | tr -d '\r' | tail -n1)"
  else
    openbao_uid="$(docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" run --rm --no-deps --entrypoint sh openbao -lc 'id -u' 2>/dev/null | tr -d '\r' | tail -n1)"
    openbao_gid="$(docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" run --rm --no-deps --entrypoint sh openbao -lc 'id -g' 2>/dev/null | tr -d '\r' | tail -n1)"
  fi
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

  if [ "$compose_run_supports_no_build" = "true" ]; then
    docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" run --rm --no-deps --no-build --user 0:0 --entrypoint sh openbao -lc "mkdir -p /openbao/data && chown -R ${openbao_uid}:${openbao_gid} /openbao/data && chmod -R u+rwX,g+rwX,o+rwX /openbao/data"
  else
    docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" run --rm --no-deps --user 0:0 --entrypoint sh openbao -lc "mkdir -p /openbao/data && chown -R ${openbao_uid}:${openbao_gid} /openbao/data && chmod -R u+rwX,g+rwX,o+rwX /openbao/data"
  fi
}

wait_for_openbao_reachable() {
  local i
  local health_code

  i=1
  while [ $i -le 60 ]; do
    health_code="$(curl -s -o /dev/null -w '%{http_code}' "$OPENBAO_LOCAL_ADDR/v1/sys/health" || true)"
    case "$health_code" in
      200|429|472|473|501|503)
        OPENBAO_HEALTH_CODE="$health_code"
        return 0
        ;;
    esac
    sleep 2
    i=$((i + 1))
  done

  return 1
}

print_openbao_manual_init_steps() {
  echo "OpenBao is running but not initialized (manual mode)." >&2
  echo "Follow initialization steps in: docs/local-first-start.md" >&2
}

require_non_empty_env_value "GRAFANA_ADMIN_USER"
require_non_placeholder_env_value "GRAFANA_ADMIN_PASSWORD"
require_non_empty_env_value "TOLGEE_INITIAL_USERNAME"
require_non_placeholder_env_value "TOLGEE_INITIAL_PASSWORD"
require_non_placeholder_env_value "TOLGEE_JWT_SECRET"
require_min_length_env_value "TOLGEE_JWT_SECRET" 32

docker network create "$OPS_SHARED_NETWORK" >/dev/null 2>&1 || true
prepare_openbao_volume_permissions
compose_ops up -d openbao

if ! wait_for_openbao_reachable; then
  echo "OpenBao did not become reachable in time. Continuing with the rest of the stack." >&2
  compose_ops logs --no-color --tail=80 openbao || true
  compose_ops up -d
  echo "Ops stack started (OpenBao status unknown)." >&2
  exit 0
fi

case "$OPENBAO_HEALTH_CODE" in
  200|429|472|473)
    echo "OpenBao is ready (initialized + unsealed)."
    ;;
  501)
    print_openbao_manual_init_steps
    ;;
  503)
    echo "OpenBao is sealed (manual mode)." >&2
    echo "Unseal it when needed. See docs/local-first-start.md (OpenBao UI steps)." >&2
    ;;
  *)
    echo "Unexpected OpenBao health status code: $OPENBAO_HEALTH_CODE (continuing)." >&2
    ;;
esac

compose_ops up -d
echo "Ops stack started."
