# OpenBao sealed

**Alert:** `OpenBaoSealed` (page)

## What fired

OpenBao is running and answering scrapes, but it is sealed. A sealed OpenBao
holds its storage encryption key nowhere it can reach, so it serves no secrets
to anyone.

Production auto-unseals through AWS KMS, so after a normal restart it should
never reach this state. This alert firing means one of a small set of things,
listed under **What to do**.

Local is different by design: it has no KMS and uses the Shamir seal, so a local
OpenBao starts sealed on every process start and is unsealed by
`scripts/local-openbao-unseal.sh`.

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

Run that on the host too — port 8200 is bound to `127.0.0.1` and is not reachable
from anywhere else.

`sealed: true` confirms it, and `recovery_seal: true` confirms the KMS seal is
in use. `sys/health` is the same signal as an HTTP status: `200` unsealed, `503`
sealed, `501` never initialized.

## What to do

Work out which of these it is. They need different fixes.

1. **The seal migration has not been run yet.** Expected exactly once, on the
   first deploy after auto-unseal was introduced. OpenBao is still a Shamir
   cluster and will not use KMS until it is migrated. Finish the migration in
   [cloud-first-deploy.md](../cloud-first-deploy.md); until then, unseal by hand
   with your key.

2. **Somebody sealed it.** `bao operator seal`, or the UI. Unseal it:

   Production OpenBao runs on the EC2 host, not on your machine, and an SSM
   session lands as `ssm-user`, which is not in the `docker` group. So: open a
   session, then `sudo`.

   ```bash
   AWS_PROFILE=platform-ops aws ssm start-session --region eu-west-1 \
     --target "$(terraform -chdir=infra/terraform/aws-compose output -raw instance_id)"
   ```

   ```bash
   sudo docker exec -it -e BAO_ADDR=http://127.0.0.1:8200 \
     platform-ops-prod-openbao-1 bao operator unseal
   ```

   `docker exec` on the container name rather than `docker compose exec`, because
   the prod compose file lives under whichever release directory is current.

   With the KMS seal in place this takes a **recovery key**, not the old unseal
   key. They are the same strings you got from `operator init`, but they play a
   different role now.

3. **Auto-unseal partially failed.** Rare: OpenBao reached KMS at startup but
   could not complete the unseal. `docker logs platform-ops-prod-openbao-1`
   names the reason, and it is nearly always a KMS permission or key-state
   problem — the key disabled, scheduled for deletion, or the IAM user's policy
   changed.

### If OpenBao is crash-looping instead of sealed

This alert will **not** fire for that — `ServiceDown` will, because a scrape
against a dead process fails. It is worth knowing the difference, because after
auto-unseal it is the more likely failure:

OpenBao **exits** rather than starting sealed when it cannot reach its KMS key.
The log line is unmistakable:

```
Error parsing Seal configuration: error fetching AWS KMS wrapping key
information: UnrecognizedClientException: The security token included in the
request is invalid.
```

That means the credentials in `OPENBAO_UNSEAL_AWS_ACCESS_KEY_ID` /
`OPENBAO_UNSEAL_AWS_SECRET_ACCESS_KEY` are wrong, expired, or deleted. They come
from SSM at deploy and belong to the `openbao-unseal` IAM user. A different AWS
error in the same position — `AccessDeniedException`, `NotFoundException`,
`KMSInvalidStateException` — points at the key or its policy instead of the
credentials.

**Never delete the unseal KMS key.** Its ciphertext is the only thing that can
decrypt OpenBao's storage. The key has a 30-day deletion window, which is the
window you would have to notice and cancel.
