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

  # --- one health path, outside any prefix ----------------------------------
  # The estate converged on a single `GET /health`. These two checks are what
  # stop it drifting back: a split probe pair, or a Next.js route parked under
  # `/api` because that is the framework's habit.
  split=$(grep -rl 'health/liveness\|health/readiness' "$d" \
            --include='*.ts' --include='*.rs' --include='*.yml' --include='*.md' \
            --include='*.sh' --include='Dockerfile*' 2>/dev/null \
          | grep -v node_modules | grep -v '/target/' | grep -v '/dist/' \
          | grep -v '/.next/' | grep -v '/worktrees/' \
          | grep -v 'engineering-standardization/' | grep -v 'verify-standards.sh' \
          | head -3)
  if [ -n "$split" ]; then
    bad "liveness/readiness split still referenced:"
    printf '      %s\n' $split
  else
    ok "single /health path"
  fi

  if find "$d/apps" -path '*/src/app/api/health/*' -not -path '*/node_modules/*' \
       -print -quit 2>/dev/null | grep -q .; then
    bad "health parked under /api — move to src/app/health/"
  fi
done

# --- every alert can be acted on --------------------------------------------
# An alert links to a runbook so that the person woken by it has somewhere to
# start. A link that 404s is worse than no link: it promises help that is not
# there. Three of the original alerts pointed at a directory that did not exist.
printf '\n\033[1malerting\033[0m\n'
ALERTS="$ROOT/platform-ops/docker/prometheus/alerts.yml"
if [ -f "$ALERTS" ]; then
  missing=""
  total=0
  for link in $(grep -o 'runbooks/[a-z-]*\.md' "$ALERTS" | sort -u); do
    total=$((total+1))
    [ -f "$ROOT/platform-ops/docs/$link" ] || missing="$missing $link"
  done
  if [ -n "$missing" ]; then
    bad "runbook links with no file:$missing"
  else
    ok "$total runbook links resolve"
  fi

  # Severity has to match a route or the alert falls through to the default
  # receiver, which is how a 'critical' alert became the least urgent thing in
  # the file.
  strays="$(grep -o 'severity: [a-z]*' "$ALERTS" | sort -u | grep -v 'severity: page\|severity: ticket' || true)"
  if [ -n "$strays" ]; then
    bad "severity labels that match no Alertmanager route: $strays"
  else
    ok "every severity maps to a route"
  fi

  # The rendered-at-deploy config must not be committed: it holds an SMTP
  # password, and a committed one would also silently shadow the template.
  if git -C "$ROOT/platform-ops" ls-files --error-unmatch \
       docker/alertmanager/config.prod.yml >/dev/null 2>&1; then
    bad "docker/alertmanager/config.prod.yml is tracked — it is a rendered secret"
  else
    ok "prod alertmanager config is rendered, not committed"
  fi
else
  skip "no alerts.yml"
fi

# --- the vendored observability kit has not drifted -------------------------
# Vendoring is only safe if divergence is loud. This is what makes it loud.
printf '\n\033[1mobservability kit\033[0m\n'
if CHECK=1 bash "$ROOT/platform-ops/scripts/sync-observability.sh" 2>/dev/null; then
  :
else
  FAILED=$((FAILED+1))
fi

# --- the vendored design-system tokens have not drifted ---------------------
# The gap this closes: a WCAG contrast fix landed in cv's copy of
# tokens/colors.css and, with no sync and no check, never reached gpool, kini
# or trading-bot — three products stayed on colors that fail 4.5:1. Vendoring
# without a drift check is not vendoring, it's four unrelated forks that
# happen to start identical.
printf '\n\033[1mdesign-system tokens\033[0m\n'
if CHECK=1 bash "$ROOT/platform-ops/scripts/sync-design-system.sh" 2>/dev/null; then
  :
else
  FAILED=$((FAILED+1))
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32mAll checks passed.\033[0m\n'
else
  printf '\033[31m%s check(s) failed.\033[0m\n' "$FAILED"
fi
exit $((FAILED > 0))
