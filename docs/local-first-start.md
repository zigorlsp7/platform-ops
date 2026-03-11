# Local First Start (platform-ops)

Use this runbook when you are creating the full local platform from scratch.
Start here before `cv`, `gpool`, or `notifications`, because those repos depend on the shared services started by `platform-ops`.

## 1. What You Are Building

When this runbook is complete, you will have a local shared platform with:

- `OpenBao` for application secrets
- `Tolgee` for runtime translations
- `Prometheus`, `Grafana`, `Loki`, `Alertmanager`, and `Jaeger` for observability
- `OpenTelemetry Collector` for trace ingestion
- shared Docker network `platform_ops_shared` used by the app repos

## 2. Prerequisites

Run every command in this document from the `platform-ops` repo root.

Required on your machine:

- Docker Desktop or Docker Engine
- `npm`
- `openssl`
- a web browser

Optional but useful:

- `jq`

## 3. Prepare The Local Env File

Create the real local env file from the tracked example:

```bash
cp docker/.env.ops.local.example docker/.env.ops.local
```

Then edit `docker/.env.ops.local`.

Values you must set:

- `GRAFANA_ADMIN_USER`
  - local Grafana username
  - keeping the default value is fine
- `GRAFANA_ADMIN_PASSWORD`
  - local Grafana password
  - choose any strong local-only password
- `TOLGEE_INITIAL_USERNAME`
  - bootstrap Tolgee admin username
  - keeping the default value is fine
- `TOLGEE_INITIAL_PASSWORD`
  - bootstrap Tolgee admin password
  - choose any strong local-only password
- `TOLGEE_JWT_SECRET`
  - secret used internally by Tolgee
  - must be at least 32 characters

Generate a strong Tolgee JWT secret:

```bash
openssl rand -hex 32
```

Important:

- `docker/.env.ops.local` is intentionally ignored by git.
- Keep real passwords only in `docker/.env.ops.local`, never in the tracked example file.

## 4. Start The Local Stack

Start the shared platform:

```bash
npm run local:up
```

What this command does:

- creates the shared Docker network `platform_ops_shared`
- starts `openbao` first
- validates the required env values
- starts the remaining ops services

What it does not do:

- it does not initialize OpenBao
- it does not unseal OpenBao

So a first boot always requires the manual OpenBao steps below.

## 5. Initialize And Unseal OpenBao

Open the OpenBao UI:

- `http://localhost:8200/ui`

On the first run, OpenBao will be uninitialized.

Initialize it with:

- `Key shares = 1`
- `Key threshold = 1`

Save these values immediately:

- `Unseal Key 1`
- `Initial Root Token`

Treat both as real secrets:

- store them in your password manager
- do not commit them
- do not put them in tracked repo files

Then unseal OpenBao in the UI using `Unseal Key 1`.

After unsealing:

1. choose token login
2. paste `Initial Root Token`
3. sign in

## 6. Enable The `kv` Secrets Engine

The app repos expect OpenBao KV v2 secrets under paths like `kv/cv`, `kv/gpool`, and `kv/notifications`.

In the OpenBao UI:

1. open `Secrets engines`
2. choose `Enable new engine`
3. choose `KV`
4. set `Version = 2`
5. set `Path = kv`
6. save

If `kv` already exists, do nothing.

## 7. Validate The Shared Platform

Confirm the containers are up:

```bash
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml ps
```

Confirm the key services respond:

```bash
curl -fsS http://localhost:8200/v1/sys/health
curl -fsS http://localhost:3002/api/health
curl -fsS http://localhost:8090/healthz || curl -fsS http://localhost:8090/api/healthz
```

Useful local URLs:

- OpenBao UI: `http://localhost:8200/ui`
- Grafana: `http://localhost:3002`
- Tolgee: `http://localhost:8090`

If these work, the platform foundation for the app repos is ready.

## 8. Daily Commands

Start or restart the local platform:

```bash
npm run local:up
```

Stop the stack but keep volumes:

```bash
npm run local:down
```

Stop the stack and delete local volumes:

```bash
npm run local:reset
```

Important:

- resetting deletes local OpenBao, Tolgee, Grafana, Loki, and related data
- after a reset, you must initialize OpenBao again

If OpenBao restarts in the sealed state:

- open `http://localhost:8200/ui`
- unseal it again with `Unseal Key 1`

## 9. Troubleshooting

`Missing required local env file`:

- copy `docker/.env.ops.local.example` to `docker/.env.ops.local`
- fill in concrete values

OpenBao health returns `501`:

- OpenBao is running but not initialized yet
- go back to section 5

OpenBao health returns `503`:

- OpenBao is sealed
- unseal it again with `Unseal Key 1`

Grafana or Tolgee login fails after you changed bootstrap credentials:

- the service data volume may still contain the old values
- if this is only a local environment, run `npm run local:reset` and bootstrap again

You need service logs:

```bash
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml logs --no-color <service>
```

Examples:

- `openbao`
- `tolgee`
- `grafana`
- `otel-collector`

## 10. CLI Fallback (Optional)

If the UI is not available, the equivalent OpenBao CLI flow is:

```bash
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml exec -T openbao bao operator init -key-shares=1 -key-threshold=1
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml exec -T openbao bao operator unseal <UNSEAL_KEY>
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml exec -T openbao bao login <ROOT_TOKEN>
docker compose --env-file docker/.env.ops.local -f docker/compose.ops.local.yml exec -T openbao bao secrets enable -path=kv kv-v2
```

## 11. Next Step

After `platform-ops` is ready, continue with:

- `cv/docs/local-first-start.md`
- `gpool/docs/local-first-start.md`
- `notifications/docs/local-first-start.md`
