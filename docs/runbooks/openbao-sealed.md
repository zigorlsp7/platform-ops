# OpenBao sealed

**Alert:** `OpenBaoSealed` (page)

## What fired

OpenBao is running and answering scrapes, but it is sealed. A sealed OpenBao
holds its storage encryption key nowhere it can reach, so it serves no secrets
to anyone until somebody supplies the unseal key.

This is not a fault. OpenBao has no `seal` stanza, so it uses the Shamir seal
and **every process start begins sealed**. Nothing seals it; it simply never
unseals itself. The question is always "what restarted it".

## Whether it matters

Not immediately, and that is what makes it dangerous.

Applications read their secrets from OpenBao **at boot only**, through
`openbao-run.mjs` / `openbao-run.sh`. A container that is already running keeps
serving traffic and never notices. Nothing is down, no user sees anything, and
the estate looks healthy.

The bill arrives on the next restart. The boot wrappers retry for 90 seconds and
then exit; `restart: unless-stopped` restarts them, so an application that
restarts while OpenBao is sealed crash-loops on a roughly 90-second cycle until
it is unsealed. Once unsealed, everything recovers on its own within about 90
seconds — there is nothing to go and restart by hand.

Deploys fail immediately. `gpool` and `kini` break out of their OpenBao health
wait on the first 503 and exit; `notifications` waits its full 120 seconds and
then exits.

## How to see

```promql
max by (job) (vault_core_unsealed) == 0
```

`max by (job)` is load-bearing, not tidiness. OpenBao keeps publishing the
pre-unseal `vault_core_unsealed{cluster=""} 0` series alongside the live
`cluster="<id>"` series at `1` for the whole retention window, so a bare
`vault_core_unsealed == 0` fires permanently against a perfectly healthy
instance. Aggregating takes the live series.

Directly, on the host:

```bash
curl -s http://127.0.0.1:8200/v1/sys/seal-status
```

`sealed: true` confirms it. `sys/health` is the same signal as an HTTP status:
`200` unsealed, `503` sealed, `501` never initialized.

## What to do

Unseal it. The key is not in this repository, on the host, or in SSM — it is
wherever you personally keep it.

```bash
docker compose -f docker/compose.ops.prod.yml exec -T \
  -e BAO_ADDR=http://127.0.0.1:8200 openbao bao operator unseal
```

Then work out which of these restarted it, because that decides whether you
need to do anything else:

1. **An ops deploy.** Expected only when `docker/openbao/prod.hcl` actually
   changed — the deploy installs the config to a fixed host path and restarts
   OpenBao only on a real change. If OpenBao restarted on a deploy that did not
   touch that file, the stable-path mount has regressed and the container is
   being recreated for its bind-mount path again.
2. **A merged `platform-ops` PR.** release-please publishes a release,
   `deploy-ops.yml` fires on `release: published`, and the ops stack deploys.
   Land platform-ops changes and let the release settle *before* unsealing, or
   the next release re-seals it minutes later.
3. **A host reboot or Docker daemon restart.** Nothing to fix; OpenBao came back
   the only way it can.
4. **An OOM kill.** `docker inspect platform-ops-prod-openbao-1 --format
   '{{.State.OOMKilled}}'`. If true, this is really
   [host-memory.md](host-memory.md), and it will happen again.

If this alert is firing several times a week, the answer is not a faster unseal;
it is auto-unseal, which removes the human from the loop entirely.
