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
cp docker/.env.ops.local.example docker/.env.ops.local
# edit docker/.env.ops.local
bash ./scripts/local-stack-up-ops.sh
```

Expected:

- OpenBao becomes ready.
- KV mount from `OPENBAO_KV_MOUNT` exists (or is auto-created as KV v2).

## 2. Local sanity check

```bash
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml ps
```

Expected: core services show as `Up` (OpenBao, Prometheus, Grafana, Loki, Tolgee, Alertmanager, Jaeger).

## 3. Local shutdown

```bash
bash ./scripts/local-stack-down-ops.sh
```

Fully clean local reset:

```bash
bash ./scripts/local-stack-down-ops.sh --volumes
```

## 4. Prepare production runtime config

Production runtime uses a split model:

- Non-secrets: `docker/.env.ops.prod` (bundled with the release)
- Secrets: AWS SSM Parameter Store under `AWS_SSM_OPS_PREFIX` (example `/platform-ops/prod/ops`)

Required secret keys in SSM:

- `GRAFANA_ADMIN_PASSWORD`
- `TOLGEE_INITIAL_PASSWORD`
- `TOLGEE_JWT_SECRET`

Manual SSM steps are documented in:

- `docs/manual-aws-operations.md`

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

## 8. Access Ops UIs (manual SSM tunnels)

Follow:

- `docs/manual-aws-operations.md`

Notes:

- Tolgee login is controlled by `docker/tolgee/config.yaml` and auth env vars (`TOLGEE_*`).
- Jaeger and Prometheus UIs are not exposed; use Grafana for traces and metrics visualization.
- Alertmanager UI is also not exposed; use Grafana Alerting (Alertmanager datasource).
