#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 \
    --release-dir <path> \
    --region <aws-region> \
    --ops-ssm-prefix </platform-ops/prod/ops> \
    --release-tag <tag> \
    [--mode ops]
USAGE
}

RELEASE_DIR=""
AWS_REGION=""
MODE="ops"
OPS_SSM_PREFIX=""
RELEASE_TAG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --release-dir)
      RELEASE_DIR="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --ops-ssm-prefix)
      OPS_SSM_PREFIX="$2"
      shift 2
      ;;
    --release-tag)
      RELEASE_TAG="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_value() {
  local name="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "Missing required arg: $name" >&2
    usage
    exit 1
  fi
}

require_value "--release-dir" "$RELEASE_DIR"
require_value "--region" "$AWS_REGION"
require_value "--ops-ssm-prefix" "$OPS_SSM_PREFIX"
require_value "--release-tag" "$RELEASE_TAG"

if [ "$MODE" != "ops" ]; then
  echo "Invalid --mode value: $MODE (expected: ops)" >&2
  usage
  exit 1
fi

retry() {
  local attempts="$1"
  local sleep_seconds="$2"
  shift 2
  local i=1

  while true; do
    if "$@"; then
      return 0
    fi

    if [ "$i" -ge "$attempts" ]; then
      return 1
    fi

    sleep "$sleep_seconds"
    i=$((i + 1))
  done
}

install_compose_plugin_binary() {
  local compose_version="${COMPOSE_VERSION:-v2.29.7}"
  local os
  local arch_raw
  local arch
  local plugin_dir
  local plugin_path
  local url

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch_raw="$(uname -m)"

  case "$arch_raw" in
    x86_64|amd64)
      arch="x86_64"
      ;;
    aarch64|arm64)
      arch="aarch64"
      ;;
    *)
      echo "[deploy] Unsupported architecture for compose binary fallback: $arch_raw" >&2
      return 1
      ;;
  esac

  plugin_dir="/usr/local/lib/docker/cli-plugins"
  plugin_path="$plugin_dir/docker-compose"
  url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-${os}-${arch}"

  echo "[deploy] Downloading docker compose plugin binary: $url"
  mkdir -p "$plugin_dir"
  curl -fsSL "$url" -o "$plugin_path"
  chmod +x "$plugin_path"
  ln -sf "$plugin_path" /usr/local/bin/docker-compose || true
}

ensure_runtime_dependencies() {
  local packages=()

  if ! command -v aws >/dev/null 2>&1; then
    packages+=("awscli")
  fi

  if ! command -v jq >/dev/null 2>&1; then
    packages+=("jq")
  fi

  if ! command -v curl >/dev/null 2>&1; then
    packages+=("curl")
  fi

  if ! command -v docker >/dev/null 2>&1; then
    packages+=("docker")
  fi

  if [ "${#packages[@]}" -gt 0 ]; then
    if ! command -v dnf >/dev/null 2>&1; then
      echo "Missing required dependencies and dnf is unavailable for install: ${packages[*]}" >&2
      exit 1
    fi

    echo "[deploy] Installing missing runtime dependencies: ${packages[*]}"
    retry 12 10 dnf install -y "${packages[@]}"
  fi

  if command -v docker >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true
  fi

  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    echo "[deploy] Installing compose runtime (docker-compose-plugin or docker-compose)"

    set +e
    retry 3 5 dnf install -y docker-compose-plugin >/dev/null 2>&1
    plugin_rc=$?
    set -e

    if [ "$plugin_rc" -ne 0 ]; then
      set +e
      retry 3 5 dnf install -y docker-compose >/dev/null 2>&1
      legacy_rc=$?
      set -e

      if [ "$legacy_rc" -ne 0 ]; then
        echo "[deploy] Could not install compose packages via dnf (tried docker-compose-plugin and docker-compose)"
        install_compose_plugin_binary || true
      fi
    fi
  fi
}

ensure_runtime_dependencies

for cmd in aws jq docker curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing command: $cmd" >&2
    exit 1
  fi
done

run_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
    return
  fi

  echo "Missing compose runtime (tried 'docker compose' and 'docker-compose')" >&2
  exit 1
}

if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
  echo "Missing compose runtime (docker compose / docker-compose)" >&2
  exit 1
fi

prepare_openbao_volume_permissions() {
  local openbao_uid
  local openbao_gid

  set +e
  openbao_uid="$(run_compose --env-file "$OPS_ENV_FILE" -f docker/compose.ops.prod.yml run --rm --no-deps --entrypoint sh openbao -lc 'id -u' 2>/dev/null | tr -d '\r' | tail -n1)"
  openbao_gid="$(run_compose --env-file "$OPS_ENV_FILE" -f docker/compose.ops.prod.yml run --rm --no-deps --entrypoint sh openbao -lc 'id -g' 2>/dev/null | tr -d '\r' | tail -n1)"
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

  echo "[deploy] Preparing OpenBao data permissions for uid:gid ${openbao_uid}:${openbao_gid}"
  run_compose --env-file "$OPS_ENV_FILE" -f docker/compose.ops.prod.yml run --rm --no-deps --user 0:0 --entrypoint sh openbao -lc "mkdir -p /openbao/data && chown -R ${openbao_uid}:${openbao_gid} /openbao/data && chmod -R u+rwX,g+rwX,o+rwX /openbao/data"
}

if [ ! -d "$RELEASE_DIR" ]; then
  echo "Release dir not found: $RELEASE_DIR" >&2
  exit 1
fi

cd "$RELEASE_DIR"

OPS_ENV_FILE="docker/.env.ops.prod"

fetch_ssm_path_to_env_file() {
  local prefix="$1"
  local output_file="$2"
  local response
  local count

  response="$(aws ssm get-parameters-by-path --region "$AWS_REGION" --path "$prefix" --recursive --with-decryption --output json)"
  count="$(printf '%s' "$response" | jq '.Parameters | length')"

  if [ "$count" -eq 0 ]; then
    echo "No SSM parameters found under $prefix" >&2
    exit 1
  fi

  printf '%s' "$response" \
    | jq -r '.Parameters | sort_by(.Name)[] | "\(.Name | split("/") | last)=\(.Value)"' > "$output_file"

  chmod 600 "$output_file"
}

fetch_ssm_path_to_env_file "$OPS_SSM_PREFIX" "$OPS_ENV_FILE"

network_name="$(grep -E '^OPS_SHARED_NETWORK=' "$OPS_ENV_FILE" | tail -n1 | cut -d'=' -f2- || true)"
if [ -z "$network_name" ]; then
  network_name="platform_ops_shared"
fi

docker network create "$network_name" >/dev/null 2>&1 || true

prepare_openbao_volume_permissions

echo "[deploy] Starting ops stack"
run_compose --env-file "$OPS_ENV_FILE" -f docker/compose.ops.prod.yml up -d

echo "[deploy] Waiting for OpenBao health"
openbao_ready="false"
openbao_code=""
i=1
while [ $i -le 60 ]; do
  openbao_code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8200/v1/sys/health || true)"
  if [ "$openbao_code" = "200" ] || [ "$openbao_code" = "429" ]; then
    openbao_ready="true"
    break
  fi

  if [ "$openbao_code" = "501" ] || [ "$openbao_code" = "503" ]; then
    echo "[deploy] OpenBao health is $openbao_code (not initialized or sealed), continuing for ops-only deploy."
    openbao_ready="true"
    break
  fi

  sleep 2
  i=$((i + 1))
done

if [ "$openbao_ready" != "true" ]; then
  echo "OpenBao did not become ready (last_health_code=${openbao_code:-unknown})." >&2
  run_compose --env-file "$OPS_ENV_FILE" -f docker/compose.ops.prod.yml logs --no-color --tail=120 openbao || true
  exit 1
fi

run_compose --env-file "$OPS_ENV_FILE" -f docker/compose.ops.prod.yml ps

echo "[deploy] Release $RELEASE_TAG deployed successfully (mode=$MODE)"
