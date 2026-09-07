#!/usr/bin/env bash

read_env_value() {
  local env_file="$1"
  local key="$2"
  grep -E "^${key}=" "$env_file" | tail -n1 | cut -d'=' -f2- || true
}

require_env_value_in_file() {
  local env_file="$1"
  local key="$2"
  local value

  value="$(read_env_value "$env_file" "$key")"
  if [ -z "$value" ]; then
    echo "Missing required non-secret value '$key' in $env_file" >&2
    exit 1
  fi
}

upsert_env_value() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  local tmp_file

  tmp_file="$(mktemp)"
  awk -F= -v k="$key" -v v="$value" '
    BEGIN { replaced = 0 }
    $1 == k {
      if (!replaced) {
        print k "=" v
        replaced = 1
      }
      next
    }
    { print }
    END {
      if (!replaced) {
        print k "=" v
      }
    }
  ' "$env_file" > "$tmp_file"
  mv "$tmp_file" "$env_file"
}
