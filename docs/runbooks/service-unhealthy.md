# Service reports itself unhealthy

**Alert:** `ServiceUnhealthy` (page)

## What fired

`service_health_status == 0`. The process is alive and serving `/metrics`, and
its own `/health` endpoint says `error` — a dependency it cannot work without is
unreachable.

This is the gap `up` cannot see. A service with a dead database serves
`/metrics` perfectly happily, so `up` stays 1 and everything looks fine from
the outside. Before `service_health_status` existed, nothing in the estate
noticed this state at all.

## Whether it matters

Yes. `error` is reserved for dependencies the service cannot function without:
the database for the APIs, the broker for `notifications-api`. Requests are
failing or about to.

## How to see

Which component:

```promql
service_component_up == 0
```

Or ask the service directly:

```bash
curl -s https://<host>/health | jq
```

The response names every component and its state.

## What to do

Follow the component. `db` down → is Postgres running, is it accepting
connections, is the disk full. `kafka` down → see
[redpanda-down.md](redpanda-down.md).

The service usually recovers on its own once the dependency returns; the health
check re-probes rather than caching. If it does not, restart the service after
the dependency is confirmed healthy — connection pools do not always come back.
