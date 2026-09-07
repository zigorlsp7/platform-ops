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
  [ "$(tail -n1 "$ENV_FILE")" = "NEW_KEY=value" ]
  [ "$(grep -c '' "$ENV_FILE")" -eq 4 ]
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
