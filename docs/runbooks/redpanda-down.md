# Redpanda down

**Alert:** `RedpandaDown` (page)

## What fired

Prometheus cannot reach the broker's metrics endpoint. Every product in the
estate publishes through it.

## Whether it matters

Yes, and the blast radius is wide but shallow: gpool and kini go `degraded`
(email stops being queued, the products keep working),
`notifications-api` goes `error` (it has nothing to consume), and the
trading-bot services lose their data path.

Expect `ServiceDegraded`, `ServiceUnhealthy` and `ComponentDown` to fire
alongside this. They are symptoms; this is the cause.

## How to see

```bash
docker compose -f docker/compose.ops.prod.yml ps redpanda
docker logs --tail 100 platform-redpanda
rpk cluster health
```

## What to do

1. **Read the logs before restarting.** Redpanda logs its reason for stopping,
   and a restart loses it.
2. **Disk.** The broker refuses to accept writes below its free-space threshold
   and will stop rather than corrupt. See [host-disk.md](host-disk.md).
3. **Restart**, then confirm recovery in this order:
   - `rpk cluster health` reports healthy
   - `service_health_status` returns to 2 for gpool and kini (~15s)
   - consumer groups have rejoined — check
     [kafka-lag.md](kafka-lag.md)

## After recovery

Two things do not fix themselves:

- **`trading-bot-market-data` does not rejoin its consumer group.** Restart it
  explicitly.
- **Messages produced during the outage were not queued.** Nothing buffered them
  locally. Work out what was lost from the outage window.
