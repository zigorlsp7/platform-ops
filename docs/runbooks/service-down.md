# Service down

**Alert:** `ServiceDown` (page)

## What fired

Prometheus has not been able to scrape `/metrics` on this target for two
minutes. The process is not running, has stopped answering, or the network to it
is broken.

## Whether it matters

Depends entirely on which target. `up == 0` on `gpool-api` is an outage.
`up == 0` on `node-exporter` means you have lost visibility into host metrics —
serious, but nobody is being turned away.

## How to see

Every target that is down right now:

```promql
up == 0
```

Then, on the host:

```bash
docker compose -f docker/compose.ops.prod.yml ps
```

A container in `Restarting` is crash-looping; `docker logs --tail 100 <name>`
shows the reason, and it is nearly always in the last twenty lines.

## What to do

1. **Crash loop.** Read the logs before restarting anything. A container that
   restarts cleanly and then dies again has told you why, once, in the logs you
   are about to lose.
2. **Out of memory.** `docker inspect <name> --format '{{.State.OOMKilled}}'`.
   If true, this is really [host-memory.md](host-memory.md).
3. **Bad config from a deploy.** The stack renders Alertmanager's config at
   deploy; a service that will not start right after a release usually cannot
   read something it expects.
4. **Disk full.** Postgres and ClickHouse both refuse to start with no space.
   See [host-disk.md](host-disk.md).

If the service is genuinely gone and cannot be brought back quickly, that is
worth knowing about explicitly — availability alerts will not fire for it,
because a service that serves no requests has no error ratio.
