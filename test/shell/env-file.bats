setup() {
  source "$BATS_TEST_DIRNAME/../../scripts/lib/env-file.sh"
  ENV_FILE="$(mktemp)"
  printf 'APP_ENV=production\nDB_HOST=db.internal\nDB_HOST=stale.internal\n' > "$ENV_FILE"
}

teardown() {
  rm -f "$ENV_FILE"
}

@test "read_env_value returns the last definition of a duplicated key" {
  run read_env_value "$ENV_FILE" DB_HOST
  [ "$status" -eq 0 ]
  [ "$output" = "stale.internal" ]
}

@test "read_env_value keeps everything after the first equals sign" {
  printf 'SECRET=abc==\n' >> "$ENV_FILE"
  run read_env_value "$ENV_FILE" SECRET
  [ "$output" = "abc==" ]
}

@test "upsert_env_value replaces an existing key in place" {
  upsert_env_value "$ENV_FILE" APP_ENV staging
  [ "$(read_env_value "$ENV_FILE" APP_ENV)" = "staging" ]
  [ "$(grep -c '^APP_ENV=' "$ENV_FILE")" -eq 1 ]
}

@test "upsert_env_value collapses a duplicated key to one line holding the new value" {
  upsert_env_value "$ENV_FILE" DB_HOST db.example.internal
  [ "$(grep -c '^DB_HOST=' "$ENV_FILE")" -eq 1 ]
  [ "$(read_env_value "$ENV_FILE" DB_HOST)" = "db.example.internal" ]
}

@test "upsert_env_value appends a key that is not there yet" {
  upsert_env_value "$ENV_FILE" NEW_KEY value
  [ "$(tail -n1 "$ENV_FILE")" = 'NEW_KEY="value"' ]
  [ "$(read_env_value "$ENV_FILE" NEW_KEY)" = "value" ]
  [ "$(grep -c '' "$ENV_FILE")" -eq 4 ]
}

@test "upsert_env_value does not touch a key that merely shares a prefix" {
  printf 'DB_HOST_REPLICA=replica.internal\n' >> "$ENV_FILE"
  upsert_env_value "$ENV_FILE" DB_HOST db.example.internal
  [ "$(read_env_value "$ENV_FILE" DB_HOST_REPLICA)" = "replica.internal" ]
}

@test "read_env_value returns an unquoted value written by hand unchanged" {
  [ "$(read_env_value "$ENV_FILE" APP_ENV)" = "production" ]
}

@test "read_env_value returns a single-quoted value written by hand literally" {
  cat >> "$ENV_FILE" <<'LITERAL_LINE'
LITERAL='a $b \\c'
LITERAL_LINE
  [ "$(read_env_value "$ENV_FILE" LITERAL)" = 'a $b \\c' ]
}

@test "upsert_env_value keeps a value with spaces on one line" {
  upsert_env_value "$ENV_FILE" SMTP_PASSWORD 'two words here'
  [ "$(grep -c '^SMTP_PASSWORD=' "$ENV_FILE")" -eq 1 ]
  [ "$(read_env_value "$ENV_FILE" SMTP_PASSWORD)" = "two words here" ]
}

@test "upsert_env_value round-trips backslashes, quotes and dollar signs" {
  local value
  value='a\nb\\c "dq" '"'"'sq'"'"' $HOME $$ ${X}'
  upsert_env_value "$ENV_FILE" TOKEN "$value"
  [ "$(read_env_value "$ENV_FILE" TOKEN)" = "$value" ]
}

@test "load_env_file exports every key without evaluating anything" {
  local marker value
  marker="$(mktemp -u)"
  value='sp ace `touch '"$marker"'` $(touch '"$marker"') $HOME #hash ;semi'
  upsert_env_value "$ENV_FILE" SECRET "$value"
  run bash -c "source '$BATS_TEST_DIRNAME/../../scripts/lib/env-file.sh'; load_env_file '$ENV_FILE'; printf '%s|%s' \"\$SECRET\" \"\$DB_HOST\""
  [ "$status" -eq 0 ]
  [ "$output" = "$value|stale.internal" ]
  [ ! -e "$marker" ]
}

@test "a written value reaches docker compose interpolation intact" {
  command -v docker >/dev/null 2>&1 || skip "docker not available"
  docker compose version >/dev/null 2>&1 || skip "docker compose not available"
  local value compose_file
  value='sp ace `whoami` $(id -u) $HOME "dq" '"'"'sq'"'"' back\slash #hash'
  upsert_env_value "$ENV_FILE" SECRET "$value"
  compose_file="$(mktemp)"
  printf 'services:\n  app:\n    image: busybox\n    environment:\n      SECRET: ${SECRET}\n' > "$compose_file"
  run docker compose --env-file "$ENV_FILE" -f "$compose_file" config --format json
  rm -f "$compose_file"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.services.app.environment.SECRET' | sed 's/\$\$/$/g')" = "$value" ]
}

@test "upsert_env_value preserves a value containing equals signs" {
  upsert_env_value "$ENV_FILE" TOKEN 'a=b=c=='
  [ "$(read_env_value "$ENV_FILE" TOKEN)" = "a=b=c==" ]
}

@test "require_env_value_in_file passes when the key has a value" {
  run require_env_value_in_file "$ENV_FILE" APP_ENV
  [ "$status" -eq 0 ]
}

@test "require_env_value_in_file fails naming the missing key and file" {
  run require_env_value_in_file "$ENV_FILE" MISSING_KEY
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING_KEY"* ]]
  [[ "$output" == *"$ENV_FILE"* ]]
}

@test "require_env_value_in_file treats an empty value as missing" {
  printf 'EMPTY=\n' >> "$ENV_FILE"
  run require_env_value_in_file "$ENV_FILE" EMPTY
  [ "$status" -eq 1 ]
}
