# Adoption

Where each repository stands against the standard, and the order in which to
close the gaps. Read from the working copies on 2026-09-02.

`~` means present but shallow, unwired, or in one repository only.

## Status

|                            | cv  | gpool | kini | trading-bot | notifications |
| -------------------------- | --- | ----- | ---- | ----------- | ------------- |
| **Shape**                  |     |       |      |             |               |
| Node 20 pinned             | yes | yes   | yes  | no          | no (24)       |
| Next.js under `src/`       | yes | yes   | yes  | no          | n/a           |
| Dockerfile beside app      | yes | yes   | yes  | yes         | no (root)     |
| Husky actually installed   | no  | yes   | yes  | no          | no            |
| Full npm script surface    | ~   | yes   | ~    | no          | ~             |
| **CI**                     |     |       |      |             |               |
| quality                    | yes | yes   | ~    | no          | yes           |
| secrets-scan               | yes | yes   | yes  | no          | no            |
| codeql                     | yes | yes   | yes  | no          | no            |
| integration                | n/a | yes   | no   | no          | yes           |
| supply chain (SBOM, Trivy) | yes | yes   | no   | no          | no            |
| contract drift             | n/a | yes   | no   | no          | n/a           |
| **Observability**          |     |       |      |             |               |
| Traces                     | no  | yes   | no   | ~           | yes           |
| Metrics                    | no  | yes   | no   | ~           | yes           |
| Scraped                    | no  | yes   | no   | no          | yes           |
| JSON logs                  | no  | no    | no   | ~           | yes           |
| `traceId` in logs          | no  | no    | no   | no          | yes           |
| Health probes deps         | n/a | yes   | yes  | yes         | yes           |
| Health shape converged     | yes | yes   | yes  | yes         | yes           |
| Single `/health` path      | yes | yes   | yes  | yes         | yes           |
| Broker in health           | n/a | yes   | yes  | yes         | yes           |
| Dashboard                  | no  | yes   | no   | no          | yes           |
| Graceful shutdown          | n/a | no    | no   | ~           | yes           |
| **Security**               |     |       |      |             |               |
| OpenBao wrapper            | yes | yes   | no   | yes         | shell         |
| Security headers           | no  | no    | no   | no          | n/a           |
| Dependabot                 | no  | no    | no   | no          | no            |
| **Operations**             |     |       |      |             |               |
| Backups                    | no  | no    | no   | no          | no            |
| SLO + burn-rate alert      | no  | no    | no   | no          | no            |
| Runbooks                   | no  | no    | no   | no          | no            |

## Order

Phased so each stage leaves the estate coherent. Front-loaded on what is cheap
and currently dangerous rather than on what is satisfying.

### Phase 1 — stop the bleeding

Roughly one week.

1. **trading-bot CI.** Copy `cv`'s `ci.yml` and adapt: cargo fmt, clippy, cargo
   test, plus the TypeScript jobs. Add commitlint, prettier, an `engines` pin.
2. **Real health checks.** Done. kini had no health endpoint at all; gpool,
   notifications and trading-bot already probed their dependencies — the original
   audit was wrong about that. Then converged, in three steps:
   - **One path.** `/health/liveness` and `/health/readiness` are gone
     everywhere; every service answers a single `GET /health`, cv included, which
     moved off `/api/health`. The liveness/readiness trade-off this gives up is
     written down in `observability.md` — it matters only under Kubernetes.
   - **One shape.** `{ status, service, components }` on all eight services,
     with the status code set rather than thrown so the 503 body survives the
     exception filter.
   - **The broker is in it.** gpool and kini now report Kafka alongside the
     database; notifications and trading-bot already did. gpool and kini only
     produce to `notification.email.requested.v1`, so a broker outage is
     `degraded` (200) rather than `error` (503); notifications, which consumes
     it, treats the same loss as fatal. cv reports `components: {}` — it has
     nothing to depend on.

3. **Backups — deferred, still outstanding.** Nightly `pg_dump` per database,
   `bao operator raft snapshot` and a Tolgee volume archive to S3 with lifecycle
   expiry, then a restore rehearsal.

   The one Phase 1 item not done. Deferred rather than dropped, and the
   highest-severity gap left in the estate: a single EC2 host holds every
   database, every secret and every translation, and none of it is backed up.
   Open decision — cron on the host, or a scheduled workflow using the existing
   OIDC role.

4. **Security headers** on all four browser surfaces, CSP in report-only.
5. **Code scanning.** Reopened and fixed properly. CodeQL was never running
   anywhere: it needs GitHub Code Security on a private repository, so the
   workflows carried `if: !repository.private` and did nothing. Semgrep is now
   the scanner in all seven repositories, and it does not need the add-on. See
   `security.md` for what the first run found — script injection in four deploy
   workflows, TLS with certificate verification disabled, ten actions pinned to
   mutable tags, and Dependabot with no cooldown.

   **Container hardening is the backlog it left behind.** Semgrep's
   `missing-user`, `missing-user-entrypoint`, `writable-filesystem-service` and
   `no-new-privileges` rules are excluded with that reason written in the
   workflow. Running every image as a non-root user with a read-only root
   filesystem is a project, not a config line — it belongs in phase 4.

6. **Dependabot** in all seven repositories.
7. **Verify husky is installed** everywhere — `git config core.hooksPath`.
   Done, with one deliberate exception: design-system has no dependencies and no
   build, so a pre-commit hook there would mean adding husky and a node_modules
   tree to run a check CI already runs. It got CI instead — gitleaks, plus a
   check that `_ds_manifest.json` still matches the components on disk, which is
   the only way that repository can actually break.

### Phase 2 — make every service observable

Roughly two weeks. This is where the platform starts paying for itself.

1. **Extract the observability kit.** Done. `platform-ops/packages/observability/`
   is canonical; `scripts/sync-observability.sh` vendors it into gpool, kini and
   notifications; `verify-standards.sh` fails on drift. The `common/metrics` vs
   `metrics` path split is gone — everything is `src/observability/`.

   Three real defects surfaced while converging the two implementations:
   - **gpool imported `tracing` last.** Auto-instrumentation patches modules as
     they load, so `pg` and `@nestjs/core` were already loaded and never
     instrumented. Measured against notifications: gpool's traces had express
     middleware spans but no `pg.query` and no controller spans. Both services
     appeared instrumented; only one was.
   - **`OTEL_EXPORTER_OTLP_ENDPOINT` meant two different things.** The base URL
     in gpool and trading-bot, the full traces URL in notifications — with each
     compose file carrying a different value to compensate. Converged on the
     spec's meaning: base URL, kit appends the path.
   - **notifications had a dead `tracingEnabled` config field** reading
     `MANAGEMENT_TRACING_ENABLED`, a variable nothing set and nothing read.
     Tracing bootstraps before the DI container exists, so it cannot come from
     config at all. Removed.

2. **Adopt it, and add the scrape jobs.** Done for every Node service.
   - gpool, notifications: adopted. kini: adopted — it had no observability of
     any kind before this.
   - Prometheus went from 2 scrape targets to 7. The four trading-bot services
     were already serving `/metrics` and nobody was collecting it; they came up
     healthy the moment a job existed.
   - trading-bot's control-plane is Fastify, so the kit grew a `fastify.ts`
     adapter beside `nest.ts` — a pino config matching the JSON log contract,
     and an `onResponse` hook emitting `http_requests_total` /
     `http_request_duration_seconds` under the **same** names and labels as the
     Express middleware. That sameness is the point: every recording rule and
     alert aggregates `http_requests_total`, so the control-plane was scraped
     but produced nothing alertable. Its default metrics also lost the
     `trading_bot_` prefix, which had made every cross-service query special-case
     this one service.
   - The sync script now vendors per flavour: the framework-free core everywhere,
     `nest.ts` only to Nest repos, `fastify.ts` only to trading-bot. It also
     appends `.js` to relative imports for the ESM consumer, since `nodenext`
     requires the extension and the CommonJS repos must not have it.
   - trading-bot read `SERVICE_NAME` where the rest of the estate reads
     `OTEL_SERVICE_NAME`. Converged, across the control-plane and all three Rust
     crates.
   - **cv now has `/metrics`.** Next.js cannot run the Nest kit, so it got the
     small equivalent: a module-level registry, process defaults, and Core Web
     Vitals reported by the browser. `/metrics` sits outside `/api` for the same
     reason `/health` does.
   - **The three Rust services emit `http_requests_total`**, via a new
     `trading-bot/crates/observability` workspace crate — the Rust half of the
     kit. Before it they published good domain metrics and nothing the shared
     alerts could read.

3. **`traceId` in every log line.** Done for the three Node APIs — the kit's
   `JsonLogger` stamps `traceId`/`spanId` from the active span, and
   `bufferLogs` routes Nest's own bootstrap logs through it too. The Rust
   services emit JSON but carry no trace context; see below.

4. **A dashboard per service**, from one template. Done, but not the way the
   plan said. One templated dashboard (`service-overview.json`) with a `$job`
   variable beats seven near-identical files that each have to be hand-edited
   when a panel changes. `gpool-api-overview.json` was fully subsumed and is
   gone; the notifications dashboard keeps only its domain panels.

   Two supporting changes made the templating possible:
   - **Loki gained an `app` label**, promoted by Alloy from the `service` field
     of the JSON log line — the same string as the Prometheus `job`. The old
     dashboards matched on `filename=~".*/gpool-app-.*-api"`, which breaks the
     moment a container is renamed.
   - **The Loki datasource gained a derived field** that finds `traceId` in a
     log line and renders a "View trace" button into Jaeger. This is what
     item 3 was _for_: click a slow trace, get its logs; find an error log, get
     its trace. Jaeger also gained a stable `uid`, without which the link
     breaks on every reprovision.

   `traceId` is deliberately not a Loki label — one stream per trace is
   unbounded cardinality.

5. **RUM.** Partly done. The Prometheus export already existed in gpool, so the
   work was correctness rather than plumbing:
   - **FID replaced by INP.** FID stopped being a Core Web Vital in March 2024,
     and it measured the wrong thing: the delay before the _first_ interaction's
     handler started, ignoring how long the handler ran and every later
     interaction. A page could score a perfect FID while every click after the
     first took a second to paint.
   - **CLS was being divided by 1000.** It is a unitless score, not a duration,
     so it shared a `_seconds` histogram with the timings and landed in the
     bottom bucket every time. It now has its own histogram on the 0.1/0.25
     thresholds.
   - **Histogram buckets moved onto the Core Web Vitals thresholds.** The old
     set started at 0.1s, so every good INP fell in one bucket and 50ms was
     indistinguishable from 190ms.
   - **Two cardinality bombs removed.** `rum_navigation_path_length` was a gauge
     labelled `session_id` + `user_id` — one time series per anonymous visitor
     session, with the values supplied by the browser. It is now a plain
     histogram. And the `page` label came from the raw pathname, so
     `/pools/<uuid>/accept` was a distinct series per pool; it is now normalised
     to a route pattern, the same way the HTTP middleware labels on the route
     rather than the resolved path.

   **Still open:** the RUM code lives in gpool, not the kit, so cv and kini have
   no RUM. Promoting it needs the client half split from the Nest half.

6. **Rust tracing.** Done. The three Rust services had **no OpenTelemetry
   crate at all** — they read `OTEL_EXPORTER_OTLP_ENDPOINT` purely to report
   `otel_exporter_configured: true` in their status, a flag asserting telemetry
   was wired when nothing was ever exported.

   They now share `crates/observability`, which carries the OTLP exporter, an
   axum middleware, and a log formatter emitting the estate's JSON shape —
   `service`, `timestamp`, `level`, `message`, `traceId` — so Alloy's `app`
   label and Grafana's trace link work for them too.

   The trap worth remembering: **`tracing-opentelemetry` exports spans, not
   events.** Wiring the exporter changed nothing at first, because the three
   crates contain no `info_span!` or `#[instrument]` anywhere — there was
   nothing to export, and nothing said so. The middleware's request span is
   currently their entire tracing surface; instrumenting the interesting
   internals is the next step.

### Phase 3 — alert on things that matter

Roughly one week, and only sensible after phase 2.

SLOs per product, burn-rate alerts against them, infrastructure alerts (disk,
consumer lag, dead letters, certificates, sealed OpenBao), a runbook per alert,
and an external uptime probe that does not run on the host it watches.

### Phase 4 — converge the structure

Started. Less mechanical than it looked — two of the first three items turned up
real problems.

1. **One Node major.** Done: every repository is on Node 24, the current LTS,
   in `engines`, `.nvmrc`, CI and every Dockerfile.

   Node 20 reached end of life in April 2026 and four repositories still
   declared it, so most of the estate was running an unsupported runtime. Worse,
   **gpool built its production images on `node:25`** while declaring
   `>=20.19.0 <21` and testing on 20 — three different majors between what CI
   proved and what shipped.

2. **One test runner.** Done: Vitest everywhere. Jest is gone from the three
   Nest APIs, `node:test` from the control-plane and platform-ops, and the two
   apps with no runner at all now have one. 332 tests pass.

   Nest needs the SWC plugin, not Vitest's default esbuild transform — esbuild
   does not implement `emitDecoratorMetadata`, so dependency injection has no
   type information and every `Test.createTestingModule` fails without it.

   Four Jest APIs have no Vitest equivalent and had to be rewritten rather than
   renamed: `done()` callbacks, `jest.requireMock`, `jest.Mock` as a type
   namespace, and the `fail()` global.

3. **Tests for cv.** Done, and for gpool's web app, which also had none. cv's
   cover the Tolgee fallback — the behaviour `/health` cites as its reason for
   reporting `ok` while Tolgee is down. platform-ops gained a `typecheck` too,
   scoped to the framework-free half of the kit.

4. **Trivy and SBOM everywhere.** Partly done. notifications has the full job.
   The `audit:prod:gate` and `.trivyignore` are in place in kini, notifications
   and trading-bot.

   **Blocked on real findings.** Turning the gate on showed kini with 8 and
   trading-bot with 7 high-severity vulnerabilities in _production_
   dependencies. Non-breaking fixes cleared some; the rest need major-version
   upgrades — `next`, `lodash`, `postcss`, `@fastify/static`. Wiring the job
   into those two repositories before that work is done would simply hold their
   pipelines red, so it waits on the upgrade.

   The upgrade that unblocked it was worth doing on its own: kini was the last
   API on NestJS 10, so moving it to 11 fixed the vulnerabilities _and_
   converged the estate. Two npm subtleties bit on the way — a stale hoisted
   `@nestjs/common@10` satisfying `^10 || ^11` peers, which needs `overrides`
   plus a regenerated lockfile, and `npm audit fix --omit=dev`, which prunes
   dev dependencies rather than leaving them alone.

5. **trading-bot's console under `src/`.** Done. It needed a `@ds/*` alias for
   the design system, which the console had been reaching through the old
   repo-wide `@/*` — that stopped working the moment `@/` meant `src/`.

   That alias has since been removed: design-system is a package, so its imports
   are bare specifiers resolved through `node_modules` like any other dependency.

6. **Contract drift for kini.** Done, with the `integration-e2e` job it needed:
   kini's CI validated its compose file but never started a stack, so there was
   no running API to export a spec from.

7. **Playwright, axe and Lighthouse budgets.** Done, on cv as the pilot.

   It found real problems on the first run: **12 WCAG AA colour-contrast
   failures**. `--ds-color-fg-subtle` was 4.16:1 and `--ds-color-fg-faint` was
   2.60:1 against the page background, both used for 11px and 12px text. The
   token scale now passes at every step in both themes.

   Performance is asserted through the Performance API rather than by running
   Lighthouse — the same Core Web Vitals numbers, in seconds instead of a
   minute, with no extra service.

8. **Container hardening.** Done. The four trading-bot images that ran as root
   now run unprivileged, and every compose service in the estate carries
   `no-new-privileges:true`. That closes the Semgrep backlog from phase 1.

### Phase 5 — maturity

Started, and further along than "ongoing" suggests.

1. **Image signing and SLSA provenance.** Done for cv, gpool and notifications —
   the three repositories that push images. Keyless cosign: a short-lived
   certificate from Fulcio bound to the workflow's OIDC identity, recorded in
   Rekor. No private key to store, rotate or leak.

   Images are signed **by digest, never by tag**. A tag can be repointed at a
   different image after signing, and the signature would still verify against
   the tag — which is exactly the attack signing is supposed to prevent.

2. **Licence scanning.** Done in all five app repositories, on production
   dependencies only: a GPL build tool that never ships imposes nothing on the
   artefact. Licences are read from the installed tree rather than the registry
   — one `npm view` per package is several minutes, and it reports what the
   registry says now rather than what actually shipped.

   One finding, the same in every repository: sharp's prebuilt libvips is
   LGPL-3.0-or-later. Allow-listed with the reasoning written beside it — sharp
   loads it as a shared library, so the obligations are attribution and the
   ability to relink, not source disclosure.

3. **Secret-expiry warnings.** Done. `scripts/check-secret-expiry.mjs` reads the
   expiry metadata OpenBao already stores and reports anything inside a 30-day
   window. It found one immediately: the local OpenBao token expires
   2026-09-26.

4. **Visual regression.** Tried on cv, then removed — and the reason it was
   removed is the more useful entry.

   It was built to cover one specific blind spot: the design system was vendored
   by copy, so a token change arrived as a silent file sync rather than a version
   bump, and nothing in the pipeline would have noticed. Screenshots were the
   only thing watching.

   That blind spot no longer exists. design-system is a package now, pinned by
   tag, so a token change arrives as a dependency bump — a visible diff in a
   reviewable pull request, in every consumer, with a version number attached.
   The thing the screenshots were compensating for got fixed at the source.

   What remained was the cost: baselines per platform (macOS and Linux, each
   generated in a matching Playwright container), rebaselining on any
   intentional change, and the standing temptation to run `--update-snapshots`
   on a red suite, which converts a failing test into a passing one that checks
   nothing. A suite that is expensive to keep honest and no longer covers a real
   gap is worse than no suite: it spends attention and returns confidence it
   hasn't earned.

5. **Feature flags.** Done, in the shared kit. Deliberately not a service:
   per-user targeting and gradual rollout are what LaunchDarkly solves and
   neither is needed here. What is needed is a declared list, a default, and the
   ability to see what is on in a running process.

   Flags are read once at startup — a flag that changes under a running process
   gives two behaviours in one request. An unregistered key throws rather than
   returning false, because a typo that silently disables a feature is far
   harder to find than one that fails at boot. Each flag carries a `removeBy`
   date, since a codebase of permanent flags has 2^n behaviours nobody has
   tested.

**Still open:** the `e2e-a11y` and visual suites run on cv only — extending them
to gpool, kini and the operator console is the obvious next step, and the
contrast fix suggests the other three will have findings too.

## How this document stays true

Update the table in the same pull request that changes the fact. A status table
that is edited later is a status table that is wrong.
