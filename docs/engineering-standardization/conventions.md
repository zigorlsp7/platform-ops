# Conventions

## Runtime

**Node 20 LTS**, pinned in every `package.json`:

```json
"engines": { "node": ">=20.19.0 <21", "npm": ">=10" }
```

`cv`, `gpool` and `kini` already pin this. `notifications` pins Node 24 and
`trading-bot` pins nothing — both are divergences to close.

Node 20 rather than 24 because three of five repositories are already on it, and
because the shared tooling — compose files, deploy scripts, GitHub Actions
setup-node steps — has to work across the estate. One runtime, one lockfile
format, one set of surprises.

Rust code pins its toolchain in `rust-toolchain.toml`.

## Package layout

Every repository is an npm workspace root with `"workspaces": ["apps/*"]`.
Applications live in `apps/<name>`, never at the repository root.

## Test runner

**Vitest** for new code. `jest` where it already exists and works — `gpool` and
`notifications` are not worth migrating for their own sake. What is not
acceptable is a single repository running both, which `kini` currently does.

Every workspace defines `test`, even if it only echoes that there are none —
`npm run test --workspaces --if-present` must never fail because a workspace
forgot to declare the script.

## Commits

Conventional commits, enforced by commitlint on `commit-msg`:

```
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`. Subject in lower case, no trailing period, body lines
wrapped at 100 characters.

`release-please` derives versions and changelogs from these, so a sloppy commit
message becomes a wrong changelog entry.

## Formatting

Prettier, with a `format` and `format:check` script at the repository root. The
`format:check` script runs in CI and must cover every file type the repository
actually contains — a glob that silently misses `.yml` is a check that passes
while the files drift.

## Frontend code layout

Next.js applications keep source under `src/`:

```
apps/<name>/src/
  app/          route handlers and pages
  components/   presentational and interactive components
  lib/          non-React helpers
  i18n/         locale resolution and message loading
```

`trading-bot`'s operator console keeps `app/`, `components/` and `lib/` at the
package root. Every path alias, lint glob and tsconfig setting differs as a
result, which is the whole cost of that divergence.

## Backend code layout

NestJS applications group by feature, with cross-cutting concerns under
`common/`:

```
apps/api/src/
  common/       logging, metrics, guards, filters — anything cross-cutting
  health/       the health module
  <feature>/    one directory per bounded concern
  main.ts
  app.module.ts
  instrumentation.ts
```

Metrics belong in `common/metrics/`. `gpool` puts them there; `notifications`
puts them in `src/metrics/`. Same job, same framework, two addresses — which is
what makes copying a fix between repositories a manual translation.
