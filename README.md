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

## Ops UI Access (Private via SSM)

Start all UI tunnels in one command:

```bash
bash ./scripts/ops-port-forward-all.sh
```

Default local URLs:

- OpenBao: `http://127.0.0.1:18200`
- Grafana: `http://127.0.0.1:13000`
- Tolgee: `http://127.0.0.1:18080`
- Alertmanager: `http://127.0.0.1:19093`
- Loki: `http://127.0.0.1:13100`

Notes:

- Tolgee auth depends on `docker/tolgee/config.yaml` plus `spring.config.additional-location` in compose (configured in this repo).
- Prometheus and Jaeger UIs are not exposed; use Grafana for metrics and traces.

Examples:

```bash
bash ./scripts/ops-port-forward-all.sh --only grafana,tolgee
bash ./scripts/ops-port-forward-all.sh --instance-id i-xxxxxxxxxxxxxxxxx
```

## Release Automation

- `.github/workflows/release-please.yml` runs on pushes to `main` and updates/creates the Release PR.
- `.github/workflows/auto-approve-release-please.yml` auto-approves Release Please PRs from `github-actions[bot]` and enables auto-merge.
- When the Release PR is merged and a GitHub Release is published, `.github/workflows/deploy-ops.yml` triggers automatically and deploys that release tag.
- Manual deploy remains available via `workflow_dispatch` in `.github/workflows/deploy-ops.yml`.
- Required secret for Release Please: `RELEASE_PLEASE_TOKEN` (PAT with `contents:write` and `pull_requests:write`; do not use `GITHUB_TOKEN`).
- Required secret for auto-approval/auto-merge: `RELEASE_PLEASE_APPROVER_TOKEN` (PAT with `pull_requests:write`; must be a different identity than `RELEASE_PLEASE_TOKEN`).
- In repository settings, enable `Allow auto-merge` (Settings -> General -> Pull Requests).

