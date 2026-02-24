#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OPS_ENV_FILE="${OPS_ENV_FILE:-$REPO_ROOT/docker/.env.ops.local}"
OPS_COMPOSE_FILE="${OPS_COMPOSE_FILE:-$REPO_ROOT/docker/compose.ops.local.yml}"

if [ ! -f "$OPS_ENV_FILE" ]; then
  echo "Missing $OPS_ENV_FILE" >&2
  exit 1
fi

failed=0

check_status() {
  local name="$1"
  local url="$2"
  local accepted_regex="$3"
  local code

  code="$(curl -s -o /tmp/platform-ops-health-body.txt -w '%{http_code}' "$url" || true)"
  if [[ "$code" =~ $accepted_regex ]]; then
    echo "[OK] $name ($url) -> $code"
  else
    echo "[FAIL] $name ($url) -> $code"
    failed=1
  fi
}

check_running_service() {
  local service="$1"
  if printf '%s\n' "$running_services" | grep -qx "$service"; then
    echo "[OK] $service container is running"
  else
    echo "[FAIL] $service container is not running"
    failed=1
  fi
}

echo "Container status:"
docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" ps || failed=1
running_services="$(docker compose --env-file "$OPS_ENV_FILE" -f "$OPS_COMPOSE_FILE" ps --services --status running || true)"

echo
echo "Service checks (internal only):"
check_running_service "prometheus"
check_running_service "jaeger"

echo
echo "HTTP checks:"
check_status "OpenBao" "http://localhost:8200/v1/sys/health" '^(200|429)$'
check_status "Alertmanager" "http://localhost:9093/-/ready" '^200$'
check_status "Grafana" "http://localhost:3002/api/health" '^200$'
check_status "Loki" "http://localhost:3100/ready" '^200$'

# Tolgee may expose either /healthz or /api/healthz depending on version/config.
tolgee_code="$(curl -s -o /tmp/platform-ops-health-body.txt -w '%{http_code}' http://localhost:8090/healthz || true)"
if [ "$tolgee_code" = "200" ]; then
  echo "[OK] Tolgee (http://localhost:8090/healthz) -> 200"
else
  check_status "Tolgee" "http://localhost:8090/api/healthz" '^200$'
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo
echo "All ops health checks passed."
