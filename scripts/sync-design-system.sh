#!/usr/bin/env bash
# Copies the canonical color tokens and per-product theme from design-system
# into each consuming app.
#
# This is deliberately narrow — tokens/colors.css and one themes/*.css per
# consumer, nothing else. design-system also ships components, styles.css,
# and a component manifest/bundle; those have their own (separate, larger)
# distribution story and are out of scope here. This script exists because of
# one specific, already-proven failure mode: a WCAG contrast fix landed in one
# vendored copy of colors.css and, with no sync and no check, never reached
# the other three. Four files, hand-copied, silently diverging is exactly the
# shape of bug this repeats until something makes divergence loud.
#
# Usage:
#   bash platform-ops/scripts/sync-design-system.sh              # every consumer
#   bash platform-ops/scripts/sync-design-system.sh kini         # just this one
#   CHECK=1 bash platform-ops/scripts/sync-design-system.sh      # report, write nothing

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/design-system"
CHECK="${CHECK:-0}"

# repo:dest_dir:theme — theme is empty for a consumer with no product theme
# (cv renders the base tokens directly, unthemed).
CONSUMERS="
gpool:apps/ui/design-system:gpool
kini:apps/ui/design-system:kini
trading-bot:apps/operator-console/design-system:operator-console
cv:apps/ui/design-system:
"

TOKENS_HEADER='/* DO NOT EDIT. Vendored from design-system/tokens/colors.css.
   Change it there and run: bash platform-ops/scripts/sync-design-system.sh */
'
THEME_HEADER_TMPL='/* DO NOT EDIT. Vendored from design-system/themes/%s.css.
   Change it there and run: bash platform-ops/scripts/sync-design-system.sh */
'

only="${1:-}"
drift=0

sync_one() {
  local repo="$1" src="$2" header="$3" dest="$4"
  local tmp
  tmp="$(mktemp)"
  { printf '%s' "$header"; cat "$src"; } > "$tmp"

  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 0
  fi

  if [ "$CHECK" = "1" ]; then
    rm -f "$tmp"
    printf '  \033[31m✗\033[0m %-14s DRIFTED: %s\n' "$repo" "${dest#"$ROOT"/}"
    drift=$((drift + 1))
  else
    mkdir -p "$(dirname "$dest")"
    mv "$tmp" "$dest"
    printf '  \033[33m→\033[0m %-14s updated: %s\n' "$repo" "${dest#"$ROOT"/}"
  fi
  return 1
}

for entry in $CONSUMERS; do
  repo="${entry%%:*}"
  rest="${entry#*:}"
  dest_dir="${rest%%:*}"
  theme="${rest##*:}"

  [ -n "$only" ] && [ "$repo" != "$only" ] && continue
  [ -d "$ROOT/$repo/.git" ] || { printf '  \033[90m–\033[0m %s (not a checkout)\n' "$repo"; continue; }

  changed=0
  sync_one "$repo" "$SRC/tokens/colors.css" "$TOKENS_HEADER" \
    "$ROOT/$repo/$dest_dir/tokens/colors.css" || changed=1

  if [ -n "$theme" ]; then
    header="$(printf "$THEME_HEADER_TMPL" "$theme")"
    sync_one "$repo" "$SRC/themes/$theme.css" "$header" \
      "$ROOT/$repo/$dest_dir/themes/$theme.css" || changed=1
  fi

  if [ "$changed" = "0" ]; then
    printf '  \033[32m✓\033[0m %-14s in sync\n' "$repo"
  fi
done

if [ "$CHECK" = "1" ] && [ "$drift" -gt 0 ]; then
  printf '\n%s file(s) out of sync. Run: bash platform-ops/scripts/sync-design-system.sh\n' "$drift" >&2
  exit 1
fi
