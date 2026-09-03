# Host disk

**Alerts:** `HostDiskFillingUp` (ticket, <15%) · `HostDiskCritical` (page, <5%)
· `HostFilesystemWillFillIn24h` (ticket)

## What fired

A filesystem is running out of space, or is on a trajectory to within a day.

## Whether it matters

This is not hypothetical. A full disk has taken this estate down twice: Tolgee's
embedded Postgres could not write, which broke translations, which broke a
product's startup. Both times the cause was Docker build cache.

`HostFilesystemWillFillIn24h` exists because a threshold alone tells you at 85%
and again at 95% and never tells you *how fast*. A slow leak and a runaway log
look identical at a single point in time.

## How to see

```promql
host:filesystem_avail:ratio
```

That recording rule is deduplicated by device, so one physical disk is one
result even when it is mounted in several places — `/var/lib` and
`/var/lib/docker` are the same `/dev/vda1`.

On the host:

```bash
docker system df
```

## What to do

In the order that reclaims the most for the least risk:

1. **Build cache** — almost always the answer.

   ```bash
   docker builder prune -af
   ```

2. **Dangling images and stopped containers.**

   ```bash
   docker image prune -af && docker container prune -f
   ```

3. **Old releases.** The deploy keeps the last five under
   `/opt/platform-ops/releases`; if pruning has been failing, they accumulate.

4. **Logs.** Compose is configured for 10MB × 3 files per container, so this
   should be bounded — if logs are large, something is not using that config.

Never `docker volume prune` while investigating. Volumes are where the databases
live.
