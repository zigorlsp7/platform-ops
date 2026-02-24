# platform-ops

Shared ops/infrastructure repo for workloads deployed on the CV platform.

## Scope

- Terraform infra for AWS deployment
- Ops docker stack (OpenBao, Prometheus, Grafana, Loki, Tolgee, OTel, Alertmanager)
- Deployment orchestration workflows and scripts

## App Integration

Application repos (for example `cv-web`) should:

1. Build and push app images.
2. Send `repository_dispatch` event `cv-web-app-release` to this repo.
3. This repo runs remote SSM deploy for app runtime.

## Bootstrap

1. Configure GitHub environment `production` with AWS role and vars.
2. Use workflow `.github/workflows/deploy-ops.yml` to deploy ops stack.
3. Use `.github/workflows/deploy-app-from-cv-web.yml` as dispatch target for app deploys.
