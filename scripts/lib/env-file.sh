#!/usr/bin/env bash

read_env_value() {
  local env_file="$1"
  local key="$2"

  grep -E "^${key}=" "$env_file" | tail -n1 | cut -d'=' -f2- | awk '
    {
      raw = $0
      n = length(raw)
      if (n >= 2 && substr(raw, 1, 1) == "\047" && substr(raw, n, 1) == "\047") {
        raw = substr(raw, 2, n - 2)
      } else if (n >= 2 && substr(raw, 1, 1) == "\"" && substr(raw, n, 1) == "\"") {
        inner = substr(raw, 2, n - 2)
        out = ""
        i = 1
        while (i <= length(inner)) {
          c = substr(inner, i, 1)
          next_c = substr(inner, i + 1, 1)
          if (c == "\\" && (next_c == "\\" || next_c == "\"")) {
            out = out next_c
            i += 2
          } else if (c == "$" && next_c == "$") {
            out = out "$"
            i += 2
          } else {
            out = out c
            i += 1
          }
        }
        raw = out
      }
      print raw
    }
  ' || true
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
  ENV_FILE_KEY="$key" ENV_FILE_VALUE="$value" awk '
    BEGIN {
      k = ENVIRON["ENV_FILE_KEY"]
      raw = ENVIRON["ENV_FILE_VALUE"]
      v = ""
      for (i = 1; i <= length(raw); i++) {
        c = substr(raw, i, 1)
        if (c == "\\" || c == "\"") {
          v = v "\\" c
        } else if (c == "$") {
          v = v "$$"
        } else {
          v = v c
        }
      }
      v = "\"" v "\""
      replaced = 0
    }
    index($0, k "=") == 1 {
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

load_env_file() {
  local env_file="$1"
  local line
  local key

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '' | '#'*) continue ;;
    esac
    key="${line%%=*}"
    case "$key" in
      '' | *[!A-Za-z0-9_]*) continue ;;
    esac
    export "$key=$(read_env_value "$env_file" "$key")"
  done < "$env_file"
}
