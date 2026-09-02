# Adoption

Where each repository stands against the standard, and the order in which to
close the gaps. Read from the working copies on 2026-09-02.

`~` means present but shallow, unwired, or in one repository only.

## Status

|                            | cv            | gpool | kini | trading-bot | notifications |
| -------------------------- | ------------- | ----- | ---- | ----------- | ------------- |
| **Shape**                  |               |       |      |             |               |
| Node 20 pinned             | yes           | yes   | yes  | no          | no (24)       |
| Next.js under `src/`       | yes           | yes   | yes  | no          | n/a           |
| Dockerfile beside app      | yes           | yes   | yes  | yes         | no (root)     |
| Husky actually installed   | no            | yes   | yes  | no          | no            |
| Full npm script surface    | ~             | yes   | ~    | no          | ~             |
| **CI**                     |               |       |      |             |               |
| quality                    | yes           | yes   | ~    | no          | yes           |
| secrets-scan               | yes           | yes   | yes  | no          | no            |
| codeql                     | yes           | yes   | yes  | no          | no            |
| integration                | n/a           | yes   | no   | no          | yes           |
| supply chain (SBOM, Trivy) | yes           | yes   | no   | no          | no            |
| contract drift             | n/a           | yes   | no   | no          | n/a           |
| **Observability**          |               |       |      |             |               |
| Traces                     | no            | yes   | no   | ~           | yes           |
| Metrics                    | no            | yes   | no   | ~           | yes           |
| Scraped                    | no            | yes   | no   | no          | yes           |
| JSON logs                  | no            | no    | no   | ~           | yes           |
| `traceId` in logs          | no            | no    | no   | no          | yes           |
| Health probes deps         | liveness only | yes   | yes  | yes         | yes           |
| Dashboard                  | no            | yes   | no   | no          | yes           |
| Graceful shutdown          | n/a           | no    | no   | ~           | yes           |
| **Security**               |               |       |      |             |               |
| OpenBao wrapper            | yes           | yes   | no   | yes         | shell         |
| Security headers           | no            | no    | no   | no          | n/a           |
| Dependabot                 | no            | no    | no   | no          | no            |
| **Operations**             |               |       |      |             |               |
| Backups                    | no            | no    | no   | no          | no            |
| SLO + burn-rate alert      | no            | no    | no   | no          | no            |
| Runbooks                   | no            | no    | no   | no          | no            |

## Order

Phased so each stage leaves the estate coherent. Front-loaded on what is cheap
and currently dangerous rather than on what is satisfying.

### Phase 1 — stop the bleeding

Roughly one week.

1. **trading-bot CI.** Copy `cv`'s `ci.yml` and adapt: cargo fmt, clippy, cargo
   test, plus the TypeScript jobs. Add commitlint, prettier, an `engines` pin.
2. **Real health checks.** Done for kini, which had no health endpoint at all.
   gpool, notifications and trading-bot already probed their dependencies — the
   original audit was wrong about this. cv stays liveness-only, which is
   defensible since it has no database, though a Tolgee readiness probe would
   improve it.
3. **Backups.** Nightly `pg_dump`, raft snapshot and Tolgee archive to S3. Then
   restore one, once.
4. **Security headers** on all four browser surfaces, CSP in report-only.
5. **Gitleaks and CodeQL** into trading-bot and notifications.
6. **Dependabot** in all seven repositories.
7. **Verify husky is installed** everywhere — `git config core.hooksPath`.

### Phase 2 — make every service observable

Roughly two weeks. This is where the platform starts paying for itself.

1. **Extract the observability kit** — `gpool`'s http metrics middleware,
   `notifications`' JsonLogger and OTel bootstrap — into one internal package
   rather than copying files. Fix the `common/metrics` path split while doing it.
2. **Adopt it in cv, kini and trading-bot.** Add their Prometheus scrape jobs.
3. **`traceId` in every log line.** The single highest-value change in the plan:
   it turns Loki and Jaeger from two tools into one.
4. **A dashboard per service**, from one template.
5. **Promote RUM** out of gpool into the shared kit, swap FID for INP, and export
   Core Web Vitals as Prometheus histograms so they can be alerted on.

### Phase 3 — alert on things that matter

Roughly one week, and only sensible after phase 2.

SLOs per product, burn-rate alerts against them, infrastructure alerts (disk,
consumer lag, dead letters, certificates, sealed OpenBao), a runbook per alert,
and an external uptime probe that does not run on the host it watches.

### Phase 4 — converge the structure

Roughly one week, mostly mechanical.

trading-bot's console under `src/`; one test runner; one Node major; tests for
cv, which has none; contract drift extended to kini; Trivy and SBOM everywhere;
Playwright, axe and Lighthouse budgets on one product as a pilot.

### Phase 5 — maturity

Ongoing. Image signing and SLSA provenance, licence scanning, secret-expiry
warnings, visual regression against the design system, feature flags before the
first risky migration rather than during it.

## How this document stays true

Update the table in the same pull request that changes the fact. A status table
that is edited later is a status table that is wrong.
