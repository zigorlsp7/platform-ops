# platform-ops

Shared operations and infrastructure repository for platform services.

## Scope

- Terraform infrastructure for AWS deployment
- Ops Docker stack (OpenBao, Prometheus, Grafana, Loki, Tolgee, OTel, Alertmanager, Jaeger)
- Deployment orchestration workflows and scripts

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

## App Deployment Handoff (optional)

Application repos can hand off deployment by sending `repository_dispatch` event type `platform-app-release`.

Workflow entrypoint in this repo:

- `.github/workflows/deploy-app-from-dispatch.yml`
