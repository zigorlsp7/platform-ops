#!/usr/bin/env bash
# Checks every repository against the standard, and prints a table.
#
# The standard says a rule you cannot verify from a terminal is a preference,
# not a standard. This is that verification. Read-only: it starts nothing,
# changes nothing, and exits non-zero if any required check fails.
#
# Usage: bash platform-ops/scripts/verify-standards.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPOS="cv gpool kini trading-bot notifications platform-ops design-system"
FAILED=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAILED=$((FAILED+1)); }
skip() { printf '  \033[90m–\033[0m %s\n' "$1"; }

for repo in $REPOS; do
  d="$ROOT/$repo"
  [ -d "$d/.git" ] || continue
  printf '\n\033[1m%s\033[0m\n' "$repo"

  # --- hooks actually installed, not merely present -------------------------
  if [ -d "$d/.husky" ]; then
    if [ "$(git -C "$d" config core.hooksPath 2>/dev/null)" != "" ]; then
      ok "husky active (hooksPath set)"
    else
      bad "husky present but INACTIVE — run 'npm install' in $repo"
    fi
  else
    skip "no .husky (design-system has no build to gate)"
  fi

  # --- dependency updates ---------------------------------------------------
  [ -f "$d/.github/dependabot.yml" ] && ok "dependabot" || bad "dependabot missing"

  # --- secret scanning ------------------------------------------------------
  [ -f "$d/.gitleaks.toml" ] && ok "gitleaks config" || skip "no gitleaks config"

  # --- CI -------------------------------------------------------------------
  if [ -f "$d/.github/workflows/ci.yml" ]; then
    jobs=$(awk '/^jobs:/{f=1;next} f && /^  [a-z]/{gsub(/:.*/,"");printf "%s ",$1}' "$d/.github/workflows/ci.yml")
    ok "ci.yml jobs: ${jobs:-none}"
    case "$jobs" in *secrets-scan*) ok "  secrets-scan job";; *) bad "  no secrets-scan job";; esac
  else
    skip "no ci.yml"
  fi

  # --- browser surfaces: security headers -----------------------------------
  for cfg in $(find "$d/apps" -maxdepth 2 -name 'next.config.*' -not -path '*/node_modules/*' 2>/dev/null); do
    app=$(basename "$(dirname "$cfg")")
    grep -q securityHeaders "$cfg" && ok "security headers ($app)" || bad "no security headers ($app)"
  done

  # --- APIs: helmet and a health endpoint -----------------------------------
  for main in $(find "$d/apps" -maxdepth 4 -name 'main.ts' -path '*/src/*' -not -path '*/node_modules/*' 2>/dev/null); do
    app=$(echo "$main" | sed "s|$d/apps/||;s|/src/main.ts||")
    grep -q helmet "$main" && ok "helmet ($app)" || bad "no helmet ($app)"
    if find "$d/apps/$app/src" -iname 'health*' -print -quit 2>/dev/null | grep -q .; then
      ok "health endpoint ($app)"
    else
      bad "no health endpoint ($app)"
    fi
  done
done

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32mAll checks passed.\033[0m\n'
else
  printf '\033[31m%s check(s) failed.\033[0m\n' "$FAILED"
fi
exit $((FAILED > 0))
