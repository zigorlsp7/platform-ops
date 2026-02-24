# platform-ops

Shared operations and infrastructure repository for platform services.

## Scope

- Terraform infrastructure for AWS deployment
- Ops Docker stack (OpenBao, Prometheus, Grafana, Loki, Tolgee, OTel, Alertmanager, Jaeger)
- Deployment orchestration workflows and scripts

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
bash ./scripts/local-stack-up-ops.sh
bash ./scripts/local-stack-health-ops.sh
```

Stop:

```bash
bash ./scripts/local-stack-down-ops.sh
```

Stop and remove volumes:

```bash
bash ./scripts/local-stack-down-ops.sh --volumes
```

## Production Deployment

1. Configure GitHub environment `production` in `platform-ops`:
- secret: `AWS_DEPLOY_ROLE_ARN`
- vars: `AWS_REGION`, `AWS_DEPLOY_BUCKET`, `AWS_DEPLOY_INSTANCE_ID`, `AWS_SSM_OPS_PREFIX`
2. Run workflow `.github/workflows/deploy-ops.yml` with `ref=main`.
3. Validate target host services using SSM and health endpoints.

Runbook: `docs/ops-runbook.md`.

## Release Automation

- `.github/workflows/release-please.yml` runs on pushes to `main` and updates/creates the Release PR.
- When the Release PR is merged and a GitHub Release is published, `.github/workflows/deploy-ops.yml` triggers automatically and deploys that release tag.
- Manual deploy remains available via `workflow_dispatch` in `.github/workflows/deploy-ops.yml`.

## App Deployment Handoff (optional)

Application repos can hand off deployment by sending `repository_dispatch` event type `platform-app-release`.

Workflow entrypoint in this repo:

- `.github/workflows/deploy-app-from-dispatch.yml`
