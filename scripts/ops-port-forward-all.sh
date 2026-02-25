#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AWS_PROFILE_NAME="${AWS_PROFILE:-platform-ops}"
AWS_REGION_NAME="${AWS_REGION:-eu-west-1}"
INSTANCE_ID="${INSTANCE_ID:-${AWS_DEPLOY_INSTANCE_ID:-}}"
ONLY_SERVICES="all"

# Format: name:remote_port:local_port:url
TUNNELS=(
  "openbao:8200:18200:http://127.0.0.1:18200"
  "grafana:3000:13000:http://127.0.0.1:13000"
  "tolgee:8080:18080:http://127.0.0.1:18080"
  "alertmanager:9093:19093:http://127.0.0.1:19093"
  "loki:3100:13100:http://127.0.0.1:13100"
)

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --instance-id <id>      EC2 instance id. If omitted, read from Terraform output.
  --profile <name>        AWS profile (default: ${AWS_PROFILE_NAME})
  --region <region>       AWS region (default: ${AWS_REGION_NAME})
  --only <csv>            Comma-separated service list (e.g. grafana,tolgee)
  -h, --help              Show help

Services: openbao,grafana,tolgee,alertmanager,loki
USAGE
}

contains_csv() {
  local csv="$1"
  local needle="$2"
  local item
  IFS=',' read -ra items <<<"$csv"
  for item in "${items[@]}"; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --instance-id)
      [ "$#" -ge 2 ] || { echo "Missing value for --instance-id" >&2; exit 1; }
      INSTANCE_ID="$2"
      shift 2
      ;;
    --profile)
      [ "$#" -ge 2 ] || { echo "Missing value for --profile" >&2; exit 1; }
      AWS_PROFILE_NAME="$2"
      shift 2
      ;;
    --region)
      [ "$#" -ge 2 ] || { echo "Missing value for --region" >&2; exit 1; }
      AWS_REGION_NAME="$2"
      shift 2
      ;;
    --only)
      [ "$#" -ge 2 ] || { echo "Missing value for --only" >&2; exit 1; }
      ONLY_SERVICES="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required" >&2
  exit 1
fi

if [ -z "$INSTANCE_ID" ] && command -v terraform >/dev/null 2>&1; then
  tf_dir="$REPO_ROOT/infra/terraform/aws-compose"
  if [ -d "$tf_dir" ]; then
    inferred_id="$(AWS_PROFILE="$AWS_PROFILE_NAME" terraform -chdir="$tf_dir" output -raw instance_id 2>/dev/null || true)"
    if [ -n "$inferred_id" ]; then
      INSTANCE_ID="$inferred_id"
    fi
  fi
fi

if [ -z "$INSTANCE_ID" ]; then
  echo "INSTANCE_ID not provided and could not be inferred from Terraform output." >&2
  echo "Pass --instance-id <id> or set INSTANCE_ID/AWS_DEPLOY_INSTANCE_ID." >&2
  exit 1
fi

if command -v lsof >/dev/null 2>&1; then
  for tunnel in "${TUNNELS[@]}"; do
    IFS=':' read -r service _remote local _url <<<"$tunnel"
    if [ "$ONLY_SERVICES" != "all" ] && ! contains_csv "$ONLY_SERVICES" "$service"; then
      continue
    fi
    if lsof -nP -iTCP:"$local" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "Local port $local is already in use; stop the process or choose another mapping." >&2
      exit 1
    fi
  done
fi

tmp_dir="$(mktemp -d /tmp/platform-ops-ssm-tunnels.XXXXXX)"
pids=()
started=0

cleanup() {
  for pid in "${pids[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  wait >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

echo "Using instance: $INSTANCE_ID"
echo "Using profile: $AWS_PROFILE_NAME"
echo "Using region:   $AWS_REGION_NAME"
echo

for tunnel in "${TUNNELS[@]}"; do
  IFS=':' read -r service remote local url <<<"$tunnel"

  if [ "$ONLY_SERVICES" != "all" ] && ! contains_csv "$ONLY_SERVICES" "$service"; then
    continue
  fi

  printf -v params '{"portNumber":["%s"],"localPortNumber":["%s"]}' "$remote" "$local"
  log_file="$tmp_dir/${service}.log"

  AWS_PROFILE="$AWS_PROFILE_NAME" aws ssm start-session \
    --target "$INSTANCE_ID" \
    --region "$AWS_REGION_NAME" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "$params" \
    >"$log_file" 2>&1 &

  pid="$!"
  pids+=("$pid")
  started=$((started + 1))

  echo "[$service] localhost:$local -> instance:$remote"
  echo "[$service] open: $url"
  echo "[$service] log:  $log_file"
  echo

done

if [ "$started" -eq 0 ]; then
  echo "No tunnels were started. Check --only value." >&2
  exit 1
fi

echo "SSM tunnels running. Press Ctrl+C to stop all tunnels."
wait
