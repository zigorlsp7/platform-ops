#!/usr/bin/env bash
# Copies the canonical observability kit into each consuming repo.
#
# The kit is vendored rather than published: seven repos across two GitHub
# owners, built by Dockerfiles whose dependency stage copies only manifests, and
# a private registry would mean a token in every CI run and a build secret in
# every image — for five files. What actually matters is that the copies cannot
# silently diverge, and `verify-standards.sh` enforces that.
#
# Usage:
#   bash platform-ops/scripts/sync-observability.sh              # every consumer
#   bash platform-ops/scripts/sync-observability.sh gpool kini   # just these
#   CHECK=1 bash platform-ops/scripts/sync-observability.sh      # report, write nothing

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/platform-ops/packages/observability"
CHECK="${CHECK:-0}"

# repo:destination:flavour — every consumer of the kit.
#
# The flavour selects which framework adapter is copied. `nest.ts` imports
# `@nestjs/common` and `fastify.ts` imports `fastify`, so syncing both
# everywhere would break the typecheck of whichever framework a service does
# not use. The core — tracing, logger, registry — goes everywhere.
CONSUMERS="
gpool:apps/api/src/observability:nest
kini:apps/api/src/observability:nest
notifications:apps/api/src/observability:nest
trading-bot:apps/control-plane/src/observability:fastify
cv:apps/ui/src/observability:next
gpool_web:apps/ui/src/observability:next
kini_web:apps/ui/src/observability:next
trading-bot_console:apps/operator-console/src/observability:next
"

# A repo may consume the kit twice — once for its API, once for its UI — so the
# repo key carries a suffix that is stripped before it is used as a path.

HEADER='// DO NOT EDIT. Vendored from platform-ops/packages/observability.
// Change it there and run: bash platform-ops/scripts/sync-observability.sh
'

# Framework-free, copied to every consumer.
CORE_FILES="tracing.ts json-logger.ts metrics.registry.ts feature-flags.ts"

drift=0
for entry in $CONSUMERS; do
  repo="${entry%%:*}"
  repo="${repo%%_*}"
  rest="${entry#*:}"
  dest="$ROOT/$repo/${rest%%:*}"
  flavour="${entry##*:}"
  [ -d "$ROOT/$repo/.git" ] || { printf '  \033[90m–\033[0m %s (not a checkout)\n' "$repo"; continue; }

  case "$flavour" in
    nest)    files="$CORE_FILES http-metrics.middleware.ts health-metrics.ts nest.ts index.nest.ts:index.ts";;
    fastify) files="$CORE_FILES fastify.ts health-metrics.ts index.fastify.ts:index.ts";;
    # UIs get RUM and the ingest/metrics handlers, but no tracing bootstrap or
    # logger — those are for a Node service that owns its process, not a page.
    next)    files="rum-client.ts rum-metrics.ts rum-ingest.ts metrics.registry.ts feature-flags.ts next.ts RumProvider.tsx index.next.ts:index.ts";;
    *)       printf '  \033[31m✗\033[0m %s: unknown flavour %s\n' "$repo" "$flavour"; drift=$((drift+1)); continue;;
  esac

  changed=""
  for spec in $files; do
    # `source:target` renames the entry point; a bare name keeps its own.
    f="${spec%%:*}"
    out="${spec##*:}"
    target="$dest/$out"
    tmp="$(mktemp)"
    { printf '%s\n' "$HEADER"; cat "$SRC/$f"; } > "$tmp"

    # ESM consumers resolve with `nodenext`, which requires an explicit `.js`
    # on every relative import; the CommonJS ones must NOT have it. One source
    # cannot satisfy both, so the extension is added on the way out.
    if [ "$flavour" = "fastify" ]; then
      sed -i '' -E "s|(from '\./[a-z.-]+)'|\1.js'|g" "$tmp" 2>/dev/null \
        || sed -i -E "s|(from '\./[a-z.-]+)'|\1.js'|g" "$tmp"
    fi

    if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
      rm -f "$tmp"
      continue
    fi

    changed="$changed $out"
    if [ "$CHECK" = "1" ]; then
      rm -f "$tmp"
    else
      mkdir -p "$dest"
      mv "$tmp" "$target"
    fi
  done

  if [ -z "$changed" ]; then
    printf '  \033[32m✓\033[0m %-14s in sync\n' "$repo"
  elif [ "$CHECK" = "1" ]; then
    printf '  \033[31m✗\033[0m %-14s DRIFTED:%s\n' "$repo" "$changed"
    drift=$((drift + 1))
  else
    printf '  \033[33m→\033[0m %-14s updated:%s\n' "$repo" "$changed"
  fi
done

if [ "$CHECK" = "1" ] && [ "$drift" -gt 0 ]; then
  printf '\n%s repo(s) out of sync. Run: bash platform-ops/scripts/sync-observability.sh\n' "$drift" >&2
  exit 1
fi
