#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_OPS_ENV_FILE="$REPO_ROOT/docker/.env.ops.local"
OPS_ENV_FILE="$DEFAULT_OPS_ENV_FILE"
OPS_COMPOSE_FILE="$REPO_ROOT/docker/compose.ops.local.yml"
REMOVE_VOLUMES="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --volumes)
      REMOVE_VOLUMES="true"
      shift
      ;;
    *)
      echo "Unknown arg: $1" >&2
      echo "Usage: $0 [--volumes]" >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$OPS_ENV_FILE" ]; then
  echo "Missing $OPS_ENV_FILE. Copy docker/.env.ops.local.example to docker/.env.ops.local and fill required values." >&2
  exit 1
fi

# Keep local startup/shutdown symmetric: load env file into shell scope.
set -a
# shellcheck disable=SC1090
source "$OPS_ENV_FILE"
set +a

args=(down --remove-orphans)
if [ "$REMOVE_VOLUMES" = "true" ]; then
  args+=(--volumes)
fi

docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" "${args[@]}"

echo "Ops stack stopped."
