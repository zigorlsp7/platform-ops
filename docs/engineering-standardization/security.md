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
