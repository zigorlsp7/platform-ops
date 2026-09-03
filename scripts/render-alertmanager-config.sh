#!/usr/bin/env bash
#
# Render docker/alertmanager/config.prod.yml.tpl into the config Alertmanager
# actually reads.
#
# Alertmanager does not expand environment variables in its config file. Before
# this script existed the prod config was written as if it did — `${SMTP_...}`
# placeholders sitting in a committed file — so every alert would have failed to
# deliver, silently, at the moment it was needed most. Rendering is the whole
# reason this file exists; treat a missing variable as a failed deploy rather
# than shipping a config with a literal `${...}` in it.
set -euo pipefail

TEMPLATE="${1:-docker/alertmanager/config.prod.yml.tpl}"
OUTPUT="${2:-docker/alertmanager/config.prod.yml}"

if [ ! -f "$TEMPLATE" ]; then
  echo "[alertmanager] Template not found: $TEMPLATE" >&2
  exit 1
fi

required=(
  SMTP_SMARTHOST
  SMTP_FROM
  SMTP_AUTH_USERNAME
  SMTP_AUTH_PASSWORD
  ALERT_EMAIL_TO
)

missing=()
for key in "${required[@]}"; do
  if [ -z "${!key:-}" ]; then
    missing+=("$key")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "[alertmanager] Cannot render config, missing: ${missing[*]}" >&2
  exit 1
fi

# Name every variable explicitly. A bare `envsubst` would also eat Alertmanager's
# own Go template syntax — `{{ .Annotations.summary }}` survives because it is
# not shell syntax, but `$labels`-style text in any future receiver would not.
envsubst '$SMTP_SMARTHOST $SMTP_FROM $SMTP_AUTH_USERNAME $SMTP_AUTH_PASSWORD $ALERT_EMAIL_TO' \
  <"$TEMPLATE" >"$OUTPUT.tmp"

# Comment lines are exempt: the template's own header explains the placeholder
# problem, and quoting an example of it is not the same as failing to expand one.
if grep -vE '^[[:space:]]*#' "$OUTPUT.tmp" | grep -q '\${'; then
  echo "[alertmanager] Rendered config still contains unexpanded placeholders:" >&2
  grep -nvE '^[[:space:]]*#' "$OUTPUT.tmp" | grep '\${' >&2
  rm -f "$OUTPUT.tmp"
  exit 1
fi

# The rendered file holds an SMTP password.
mv "$OUTPUT.tmp" "$OUTPUT"
chmod 600 "$OUTPUT"
echo "[alertmanager] Rendered $OUTPUT"
