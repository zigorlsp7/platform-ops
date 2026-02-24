#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 --file <env-file> --prefix </ssm/prefix> --region <aws-region> [--secure-keys key1,key2] [--dry-run]

Examples:
  $0 --file docker/.env.app.prod --prefix /cv-web/prod/app --region us-east-1 --secure-keys OPENBAO_TOKEN,DB_PASSWORD,POSTGRES_PASSWORD
  $0 --file docker/.env.ops.prod --prefix /cv-web/prod/ops --region us-east-1 --secure-keys OPENBAO_DEV_ROOT_TOKEN,GRAFANA_ADMIN_PASSWORD
USAGE
}

ENV_FILE=""
SSM_PREFIX=""
AWS_REGION=""
SECURE_KEYS_CSV=""
DRY_RUN="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --file)
      ENV_FILE="$2"
      shift 2
      ;;
    --prefix)
      SSM_PREFIX="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --secure-keys)
      SECURE_KEYS_CSV="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
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

if [ -z "$ENV_FILE" ] || [ -z "$SSM_PREFIX" ] || [ -z "$AWS_REGION" ]; then
  usage
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Env file not found: $ENV_FILE" >&2
  exit 1
fi

if [ "${SSM_PREFIX:0:1}" != "/" ]; then
  echo "SSM prefix must start with '/': $SSM_PREFIX" >&2
  exit 1
fi

contains_key() {
  local key="$1"
  local csv="$2"
  local old_ifs="$IFS"
  IFS=','
  for item in $csv; do
    if [ "$item" = "$key" ]; then
      IFS="$old_ifs"
      return 0
    fi
  done
  IFS="$old_ifs"
  return 1
}

uploaded=0

while IFS= read -r raw || [ -n "$raw" ]; do
  line="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  if [ -z "$line" ] || [ "${line#\#}" != "$line" ]; then
    continue
  fi

  if [ "${line#*=}" = "$line" ]; then
    continue
  fi

  key="${line%%=*}"
  value="${line#*=}"

  key="$(printf '%s' "$key" | sed 's/[[:space:]]*$//')"

  if [ -z "$key" ]; then
    continue
  fi

  parameter_name="${SSM_PREFIX%/}/$key"
  parameter_type="String"

  if [ -n "$SECURE_KEYS_CSV" ] && contains_key "$key" "$SECURE_KEYS_CSV"; then
    parameter_type="SecureString"
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] put-parameter name=$parameter_name type=$parameter_type"
  else
    aws ssm put-parameter \
      --region "$AWS_REGION" \
      --name "$parameter_name" \
      --value "$value" \
      --type "$parameter_type" \
      --overwrite >/dev/null
    echo "Uploaded $parameter_name ($parameter_type)"
  fi

  uploaded=$((uploaded + 1))
done < "$ENV_FILE"

if [ "$uploaded" -eq 0 ]; then
  echo "No env entries found in $ENV_FILE" >&2
  exit 1
fi

echo "Processed $uploaded parameters from $ENV_FILE"
