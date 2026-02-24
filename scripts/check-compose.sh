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
trap 'rm -f "$local_tmp" "$prod_tmp"' EXIT

docker compose --env-file "$REPO_ROOT/docker/.env.ops.local" -f "$REPO_ROOT/docker/compose.ops.local.yml" config > "$local_tmp"
docker compose --env-file "$REPO_ROOT/docker/.env.ops.prod" -f "$REPO_ROOT/docker/compose.ops.prod.yml" config > "$prod_tmp"

echo "Compose config render passed (local + prod)."
