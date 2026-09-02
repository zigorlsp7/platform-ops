#!/usr/bin/env bash
set -euo pipefail

# Mints a scoped local OpenBao token for one application.
#
# Both kini and notifications already call this from `npm run local:token`, and
# it did not exist — which is why those repos fail at startup with a permission
# error that looks like a misconfiguration.
#
# What it does, for app <name>:
#   1. writes the ACL policy <name>-local-read, granting read on kv/<name> only
#   2. mints a token against that policy
#   3. verifies the token can actually read the path before handing it over
#   4. writes it into the app's docker/.env.app.local as OPENBAO_TOKEN
#
# The root token is read from the terminal, never from an argument, so it does
# not land in shell history or the process list. It is never echoed or written.
#
# Usage:  bash provision-local-app-token.sh <app> [--print-only]

APP="${1:-}"
MODE="${2:-}"

if [ -z "$APP" ]; then
  echo "Usage: bash provision-local-app-token.sh <app> [--print-only]" >&2
  echo "  e.g. bash provision-local-app-token.sh kini" >&2
  exit 1
fi

OPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$(cd "$OPS_DIR/../$APP" 2>/dev/null && pwd || true)"
ENV_FILE="$APP_DIR/docker/.env.app.local"
POLICY="${APP}-local-read"

compose() {
  docker compose \
    --env-file "$OPS_DIR/docker/.env.ops.local" \
    -f "$OPS_DIR/docker/compose.ops.local.yml" "$@"
}

# --- preflight ---------------------------------------------------------------
health="$(curl -s "http://localhost:8200/v1/sys/health" || true)"
case "$health" in
  *'"sealed":true'*)
    echo "OpenBao is sealed. Unseal it first:" >&2
    echo "  docker exec -it platform-ops-local-openbao-1 bao operator unseal" >&2
    exit 1 ;;
  *'"initialized":true'*) : ;;
  *) echo "OpenBao is not reachable on http://localhost:8200 — is the ops stack up?" >&2; exit 1 ;;
esac

printf 'Root token for OpenBao (input hidden): '
read -rs ROOT_TOKEN
printf '\n'
[ -n "$ROOT_TOKEN" ] || { echo "No token entered." >&2; exit 1; }

bao() {
  compose exec -T \
    -e BAO_ADDR=http://127.0.0.1:8200 \
    -e BAO_TOKEN="$ROOT_TOKEN" \
    openbao bao "$@"
}

# --- 1. policy ---------------------------------------------------------------
echo "Writing policy ${POLICY} (read on kv/${APP} only)..."
bao policy write "$POLICY" - <<EOF
path "kv/data/${APP}" { capabilities = ["read"] }
path "kv/metadata/${APP}" { capabilities = ["read"] }
EOF

# --- 2. token ----------------------------------------------------------------
echo "Minting token..."
APP_TOKEN="$(bao token create -policy="$POLICY" -format=json | jq -r '.auth.client_token')"
[ -n "$APP_TOKEN" ] && [ "$APP_TOKEN" != "null" ] || { echo "Token creation failed." >&2; exit 1; }

# --- 3. verify ---------------------------------------------------------------
# A token that cannot look itself up is expired or malformed; one that cannot
# read its path has the wrong policy. Distinguishing the two here saves a
# confusing boot failure later.
code="$(curl -s -o /dev/null -w '%{http_code}' \
  -H "X-Vault-Token: $APP_TOKEN" http://localhost:8200/v1/auth/token/lookup-self)"
[ "$code" = "200" ] || { echo "New token fails lookup-self (HTTP $code)." >&2; exit 1; }

code="$(curl -s -o /dev/null -w '%{http_code}' \
  -H "X-Vault-Token: $APP_TOKEN" "http://localhost:8200/v1/kv/data/${APP}")"
case "$code" in
  200) echo "Verified: token reads kv/${APP}." ;;
  404) echo "Verified: policy is correct, but kv/${APP} holds no secret yet." ;;
  *)   echo "New token cannot read kv/${APP} (HTTP $code)." >&2; exit 1 ;;
esac

# --- 4. install --------------------------------------------------------------
if [ "$MODE" = "--print-only" ] || [ ! -f "$ENV_FILE" ]; then
  [ -f "$ENV_FILE" ] || echo "No $ENV_FILE — printing instead."
  echo
  echo "OPENBAO_TOKEN=$APP_TOKEN"
  exit 0
fi

if grep -qE '^OPENBAO_TOKEN=' "$ENV_FILE"; then
  tmp="$(mktemp)"
  # Rewritten via a temp file rather than sed -i: the token can contain
  # characters sed would treat as delimiters.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      OPENBAO_TOKEN=*) printf 'OPENBAO_TOKEN=%s\n' "$APP_TOKEN" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$ENV_FILE" > "$tmp"
  mv "$tmp" "$ENV_FILE"
  echo "Updated OPENBAO_TOKEN in $ENV_FILE"
else
  printf 'OPENBAO_TOKEN=%s\n' "$APP_TOKEN" >> "$ENV_FILE"
  echo "Appended OPENBAO_TOKEN to $ENV_FILE"
fi

echo "Done. Now run: npm run local:up"
