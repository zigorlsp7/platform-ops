# Repository shape

## Required layout

```
<repo>/
  apps/<name>/            one directory per deployable
    Dockerfile            beside the app it builds, never at the repo root
  docker/
    compose.app.local.yml
    compose.app.prod.yml
    .env.app.local.example
  docs/
    local-first-start.md  how to run it on a laptop, from nothing
    cloud-first-deploy.md how it reaches production
  scripts/
    local-stack-up.sh
    local-stack-down.sh
    local-stack-reset.sh
    openbao-run.mjs       the boot-time secret wrapper
    precommit-gitleaks.sh
    prepare-husky.mjs
  .husky/
    pre-commit
    commit-msg
  commitlint.config.js
  package.json
```

`notifications` keeps its Dockerfile at the repository root and still carries a
`target/` directory from its Java incarnation. Both are legacy, not variation.

## The npm script surface

These names are the interface. Anyone moving between repositories should not
have to read `package.json` to find out how to start something.

| Script                      | Does                                             |
| --------------------------- | ------------------------------------------------ |
| `local:up`                  | Brings the app up against the shared platform    |
| `local:down`                | Stops it                                         |
| `local:reset`               | Stops it and discards its local state            |
| `local:token`               | Mints a scoped OpenBao token and installs it     |
| `lint`                      | Lints every workspace                            |
| `typecheck`                 | Typechecks every workspace                       |
| `build`                     | Builds every workspace                           |
| `test`                      | Runs every workspace's tests                     |
| `format` / `format:check`   | Writes / verifies formatting                     |
| `ci:quality:local`          | lint + typecheck + build + test, as CI runs them |
| `test:secrets:gitleaks`     | Secret scan                                      |
| `precommit:checks`          | What the pre-commit hook runs                    |
| `audit` / `audit:prod:gate` | Dependency audit, and the gate CI uses           |

`local:up` is always `bash ./scripts/local-stack-up.sh`. The shell script is the
implementation; the npm name is the contract. Every product already does this —
it is recorded here so it stays true.

`notifications` is missing `precommit:checks`, `test:secrets:gitleaks` and
`prepare`, and names its quality script `ci:quality` rather than
`ci:quality:local`. `trading-bot` is missing most of the surface entirely.

## Husky must be installed, not merely present

A `.husky/` directory with hooks in it proves nothing. If `prepare` has not run,
`core.hooksPath` is unset and **every hook is silently skipped** — commits pass
with no lint, no typecheck, no commitlint, and no secret scan, while the
repository looks fully gated.

This is not hypothetical: it was true of `cv` for its entire history, and eight
commits were made under it before anyone noticed.

Verify, do not assume:

```bash
git config core.hooksPath   # must print .husky
```

If it prints nothing, run `npm install` to trigger `prepare`.

## Secrets never live in the repository

`docker/.env.app.local` holds the OpenBao token and is gitignored in every
repository. The example file beside it is committed and contains no values.

Generated artefacts — PDFs, coverage, SBOMs, build output — are gitignored too. A
committed build artefact goes stale against the source that claims to produce it.
