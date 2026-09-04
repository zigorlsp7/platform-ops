# Component unreachable

**Alert:** `ComponentDown` (ticket)

## What fired

A named dependency of a service has been unreachable for five minutes.
`{{ component }}` says which: `db` or `kafka`.

This alert overlaps `ServiceUnhealthy` and `ServiceDegraded` on purpose. Those
report what the _service_ concluded; this reports the raw fact per dependency,
which is what you want when several services share one broker and you are trying
to tell "the broker is down" from "one service cannot reach the broker".

## Whether it matters

Read it alongside the others:

- Firing with `ServiceUnhealthy` → the dependency is required. Act now.
- Firing with `ServiceDegraded` → optional. See
  [service-degraded.md](service-degraded.md).
- Firing for one service while others are fine → the dependency is up and _this_
  service cannot reach it. Network, credentials, or a stale connection pool.

## How to see

```promql
sum by (component) (service_component_up == 0)
```

If every service reports the same component down, it is the component. If one
does, it is that service.

## What to do

- **`db`** — is Postgres running, is it out of connections
  (`pg_stat_activity`), is the disk full.
- **`kafka`** — [redpanda-down.md](redpanda-down.md).
- **One service only** — restart it. The probe uses a fresh admin client per
  check, but the application's own producer may be holding a dead connection.
