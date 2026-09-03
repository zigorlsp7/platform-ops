# Host memory pressure

**Alert:** `HostMemoryPressure` (ticket)

## What fired

Less than 10% of host memory has been available for fifteen minutes.

## Whether it matters

Yes, because of what happens next rather than what is happening now. The kernel
picks a victim, and here it reliably picks ClickHouse — which takes
`trading-bot-market-data` and `trading-bot-research-backtesting` with it. None of
those containers has a memory limit set, so nothing bounds the problem before
the OOM killer does.

## How to see

```promql
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
```

Per container, on the host:

```bash
docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}'
```

Whether something was already killed:

```bash
docker inspect <name> --format '{{.State.OOMKilled}}'
```

## What to do

1. **Identify the grower.** ClickHouse and the JVM services (Tolgee) are the
   usual candidates.
2. **Restart the offender** to reclaim immediately — this is a stopgap, not a
   fix.
3. **Set a limit.** The real fix is `mem_limit` on the container, so it dies
   predictably and alone rather than taking the host's other tenants with it.
   Absent limits are a known outstanding item for the trading-bot stack.

If pressure is steady rather than growing, the host is simply too small for what
is on it, and the answer is a decision rather than a command.
