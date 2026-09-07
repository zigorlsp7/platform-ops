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

# --- the design-system is a dependency, and one version of it ---------------
# This used to be a token-drift check over four vendored copies, because a
# WCAG contrast fix had landed in cv's copy of colors.css and never reached
# the other three. The copies are gone — design-system is a package now — so
# the failure mode moved rather than disappeared: a consumer that re-vendors
# it, or four consumers sitting on four different tags, gets back exactly the
# divergence the copies produced.
printf '\n\033[1mdesign-system consumers\033[0m\n'
DS_VERSIONS=""
for repo in cv gpool kini trading-bot; do
  d="$ROOT/$repo"
  [ -d "$d/.git" ] || continue

  # A re-vendored tree is the old bug walking back in. Look for actual sources,
  # not the directory: an emptied one lingers on any machine that dropped a
  # .DS_Store in it, and a check that cries wolf is a check people stop reading.
  vendored=$(find "$d/apps" -maxdepth 2 -type d -name design-system -not -path '*/node_modules/*' 2>/dev/null \
             | xargs -I{} find {} -name '*.jsx' -o -name 'styles.css' 2>/dev/null | head -1)
  [ -n "$vendored" ] && bad "$repo: vendored sources under ${vendored#"$d"/} — it should be a dependency"

  pkg=$(find "$d/apps" -maxdepth 2 -name package.json -not -path '*/node_modules/*' 2>/dev/null \
        | xargs grep -l '"design-system"' 2>/dev/null | head -1)
  if [ -z "$pkg" ]; then
    skip "$repo: does not use design-system"
    continue
  fi

  ref=$(sed -n 's/.*"design-system": *"\([^"]*\)".*/\1/p' "$pkg" | head -1)
  case "$ref" in
    *'#'*) ok "$repo: ${ref##*#}"; DS_VERSIONS="$DS_VERSIONS ${ref##*#}" ;;
    *)     bad "$repo: design-system is unpinned ($ref) — pin it to a tag" ;;
  esac
done

distinct=$(printf '%s\n' $DS_VERSIONS | sort -u | wc -l | tr -d ' ')
if [ "$distinct" -gt 1 ]; then
  bad "consumers are on $distinct different versions:$(printf '%s\n' $DS_VERSIONS | sort -u | tr '\n' ' ')"
elif [ "$distinct" = 1 ]; then
  ok "all consumers on the same tag"
fi

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32mAll checks passed.\033[0m\n'
else
  printf '\033[31m%s check(s) failed.\033[0m\n' "$FAILED"
fi
exit $((FAILED > 0))
