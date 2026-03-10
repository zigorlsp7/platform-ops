# Local First Start (platform-ops)

Use this runbook the first time you start `platform-ops` locally, or after a local volume reset.

## 1. Prerequisites

From your machine:

- Docker Desktop (or Docker Engine) is running.
- `npm` is installed.

## 2. Prepare Local Env File

Edit `docker/.env.ops.local` and set concrete values for:

- `GRAFANA_ADMIN_USER`
- `GRAFANA_ADMIN_PASSWORD`
- `TOLGEE_INITIAL_USERNAME`
- `TOLGEE_INITIAL_PASSWORD`
- `TOLGEE_JWT_SECRET` (must be at least 32 chars)

Generate a strong Tolgee JWT secret:

```bash
openssl rand -hex 32
```

## 3. Start Local Stack

From repo root:

```bash
npm run local:up
```

The script starts the full local ops stack. OpenBao initialization/unseal is still manual.

## 4. Open OpenBao UI

- Open `http://localhost:8200/ui` in your browser.
- You should see OpenBao in uninitialized state.

## 5. Initialize OpenBao in UI (First Time Only)

In the UI:

- Set `Key shares = 1`
- Set `Key threshold = 1`
- Click initialize

Save these generated values:

- `Unseal Key 1`
- `Initial Root Token`

Store them in your password manager (do not commit them to the repo).

## 6. Unseal OpenBao in UI

In the UI unseal page:

- Paste `Unseal Key 1`
- Submit unseal

## 7. Login in UI

In the UI:

- Login using token method
- Paste `Initial Root Token`
- Sign in

## 8. Enable KV Mount in UI (First Time Only)

In the UI:

- Go to secrets engines
- Enable new engine
- Type: `KV`
- Version: `2`
- Path: `kv`
- Save

If `kv/` already exists, skip this step.

## 9. Validate Services

```bash
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml ps
curl -fsS http://localhost:8200/v1/sys/health
curl -fsS http://localhost:3002/api/health
curl -fsS http://localhost:8090/healthz || curl -fsS http://localhost:8090/api/healthz
```

## 10. Daily Restart Note

If OpenBao restarts in sealed state:

- open `http://localhost:8200/ui`
- unseal with `Unseal Key 1`

## 11. CLI Fallback (Optional)

If you cannot access the UI, use the CLI equivalents:

```bash
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml exec -T openbao bao operator init -key-shares=1 -key-threshold=1
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml exec -T openbao bao operator unseal <UNSEAL_KEY>
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml exec -T openbao bao login <ROOT_TOKEN>
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml exec -T openbao bao secrets enable -path=kv kv-v2
```
