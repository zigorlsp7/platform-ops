#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OPENBAO_LOCAL_ADDR="${OPENBAO_LOCAL_ADDR:-http://127.0.0.1:8200}"
KEY_FILE="${OPENBAO_LOCAL_UNSEAL_KEY_FILE:-$REPO_ROOT/docker/.openbao-local-unseal-key}"

read_seal_status() {
  curl -s -o /dev/null -w '%{http_code}' "$OPENBAO_LOCAL_ADDR/v1/sys/health" || true
}

print_manual_steps() {
  echo "OpenBao is sealed and no local unseal key is available." >&2
  echo "Unseal it in the UI at $OPENBAO_LOCAL_ADDR/ui, or write your key to:" >&2
  echo "  $KEY_FILE" >&2
  echo "That file is gitignored and is read only by this script." >&2
}

health_code="$(read_seal_status)"

case "$health_code" in
  200|429|472|473)
    echo "OpenBao is already unsealed."
    exit 0
    ;;
  501)
    echo "OpenBao is not initialized yet. See docs/local-first-start.md." >&2
    exit 0
    ;;
  503) ;;
  *)
    echo "OpenBao is not reachable at $OPENBAO_LOCAL_ADDR (health=$health_code)." >&2
    exit 0
    ;;
esac

unseal_key="${OPENBAO_LOCAL_UNSEAL_KEY:-}"

if [ -z "$unseal_key" ] && [ -f "$KEY_FILE" ]; then
  unseal_key="$(tr -d '\r\n' <"$KEY_FILE")"
fi

if [ -z "$unseal_key" ]; then
  print_manual_steps
  exit 0
fi

response_code="$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST \
  --data-binary @- \
  "$OPENBAO_LOCAL_ADDR/v1/sys/unseal" <<JSON || true
{"key":"$unseal_key"}
JSON
)"

unset unseal_key

if [ "$response_code" != "200" ]; then
  echo "OpenBao unseal request failed (http=$response_code)." >&2
  echo "Check the key in $KEY_FILE, or unseal in the UI." >&2
  exit 1
fi

health_code="$(read_seal_status)"

case "$health_code" in
  200|429|472|473)
    echo "OpenBao unsealed."
    ;;
  *)
    echo "OpenBao still reports health=$health_code after unsealing." >&2
    exit 1
    ;;
esac
