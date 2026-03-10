# platform-ops

Shared operations and infrastructure repository for platform services.

## Scope

- Terraform infrastructure for AWS deployment
- Ops Docker stack (OpenBao, Prometheus, Grafana, Loki, Tolgee, OTel, Alertmanager, Jaeger)
- Deployment orchestration workflows and scripts

## Docker Config Layout

Service configs are grouped under per-service folders in `docker/`:

- `docker/alertmanager/`
- `docker/grafana/`
- `docker/loki/`
- `docker/openbao/`
- `docker/otel/`
- `docker/prometheus/`
- `docker/tolgee/`


## Husky Commit Checks

This repo uses Husky + Node scripts for local quality gates.

Install once:

```bash
npm install
```

That installs dependencies and enables Git hooks via `prepare`.

Run checks manually:

```bash
npm run check:hooks
```

Checks include:

- gitleaks secret scan (staged files)
- shell syntax (`bash -n`)
- workflow YAML parse
- compose config render (local/prod)
- terraform fmt check

Requirements for checks:

1. `docker`
2. `terraform`
3. `ruby`
4. `gitleaks`

Install gitleaks on macOS:

```bash
brew install gitleaks
```

## Local First Validation

From repo root:

```bash
npm run local:up
```

`docker/.env.ops.local` is required and is the only local ops env source.

OpenBao local now uses production-like behavior:

- no `-dev` auto-init
- no auto-unseal
- no default dev token

First run (or after reset) requires manual OpenBao initialization and unseal. Follow `docs/local-first-start.md`.

Stop:

```bash
npm run local:down
```

Stop and remove volumes:

```bash
npm run local:reset
```

## Production Deployment

1. Configure GitHub environment `production` in `platform-ops`:
- secret: `AWS_DEPLOY_ROLE_ARN`
- vars: `AWS_REGION`, `AWS_DEPLOY_BUCKET`, `AWS_DEPLOY_INSTANCE_ID`, `AWS_SSM_OPS_PREFIX`
2. Run workflow `.github/workflows/deploy-ops.yml` with `ref=main`.
3. Validate target host services using SSM and health endpoints.

## Ops UI Access (Private via SSM)

Default local URLs once tunnels are open:

- OpenBao: `http://127.0.0.1:18200`
- Grafana: `http://127.0.0.1:13000`
- Tolgee: `http://127.0.0.1:18080`

Notes:

- Tolgee auth depends on `docker/tolgee/config.yaml` plus `spring.config.additional-location` in compose (configured in this repo).
- Prometheus and Jaeger UIs are not exposed; use Grafana for metrics and traces.
- Alert status is available in Grafana via the Alertmanager datasource.

## Release Automation

- `.github/workflows/release-please.yml` runs on pushes to `main` and creates/updates the Release Please PR.
- `.github/workflows/auto-approve-release-please.yml` auto-approves and enables auto-merge for Release Please PRs after checks pass.
- `.github/workflows/deploy-ops.yml` triggers on `release.published` and deploys the published tag automatically.
- Manual deploy remains available via `workflow_dispatch` in `.github/workflows/deploy-ops.yml`.
- Required secret for Release Please merge/release operations: `RELEASE_PLEASE_TOKEN` (PAT with `contents:write`; do not use `GITHUB_TOKEN`).
