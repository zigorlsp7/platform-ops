# Ops Runbook: Local -> Production

This runbook validates `platform-ops` independently from any application repo.

## 0. Install Husky checks (recommended)

```bash
npm install
npm run check:hooks
```

## 1. Local startup

```bash
cd <path-to-platform-ops>
bash ./scripts/local-stack-up-ops.sh
```

Expected:

- OpenBao becomes ready.
- KV mount from `OPENBAO_KV_MOUNT` exists (or is auto-created as KV v2).

## 2. Local health verification

```bash
bash ./scripts/local-stack-health-ops.sh
```

Expected all `[OK]` for:

- OpenBao
- Prometheus
- Alertmanager
- Grafana
- Loki
- Tolgee
- Jaeger

## 3. Local shutdown

```bash
bash ./scripts/local-stack-down-ops.sh
```

Fully clean local reset:

```bash
bash ./scripts/local-stack-down-ops.sh --volumes
```

## 4. Prepare production SSM values

Source of truth for runtime ops config is SSM path (example `/platform-ops/prod/ops`).

```bash
./scripts/aws-ssm-sync-env.sh \
  --file docker/.env.ops.prod \
  --prefix /platform-ops/prod/ops \
  --region eu-west-1 \
  --secure-keys GRAFANA_ADMIN_PASSWORD
```

## 5. Deploy ops on production

In GitHub repo `platform-ops`:

1. Open Actions.
2. Run workflow `Deploy AWS Ops (EC2 Compose)`.
3. Inputs:
- `ref=main`
- `release_tag` optional

## 6. Verify production ops deployment

From workflow logs confirm:

- S3 bundle upload succeeds.
- SSM command status is `Success`.
- `scripts/prod-deploy-remote.sh` logs show `mode=ops` and `Release ... deployed successfully`.

Then from SSM shell on target instance:

```bash
cd /opt/platform-ops/releases/<ops-release-tag>
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml ps
```

## 7. Troubleshooting

- `Missing command: docker` on instance:
  - `prod-deploy-remote.sh` auto-installs dependencies; if it still fails, inspect SSM command output and AMI package repositories.
- OpenBao sealed/uninitialized:
  - initialize/unseal OpenBao once and persist token/unseal procedure.
- `permission denied` for OpenBao data:
  - run deploy again after the script adjusts OpenBao volume permissions.

## 8. Access Ops UIs with one command

From repo root:

```bash
bash ./scripts/ops-port-forward-all.sh
```

Optional: only specific services:

```bash
bash ./scripts/ops-port-forward-all.sh --only grafana,tolgee
```

Press `Ctrl+C` to close all tunnels.

Notes:

- Tolgee login is controlled by `docker/tolgee/config.yaml` and auth env vars (`TOLGEE_*`).
- Jaeger and Prometheus UIs are not exposed; use Grafana for traces and metrics visualization.
- Alertmanager UI is also not exposed; use Grafana Alerting (Alertmanager datasource).
