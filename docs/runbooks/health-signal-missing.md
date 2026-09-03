# Health signal missing

**Alert:** `HealthSignalMissing` (ticket)

## What fired

A service is being scraped successfully — `up == 1` — and publishes no
`service_health_status`.

## Whether it matters

Not to users, immediately. It matters because of what it disables. Three alerts
depend on this metric existing:

- `ServiceUnhealthy` — a required dependency is unreachable
- `ServiceDegraded` — an optional one is, so email is silently not queued
- `ComponentDown` — per-dependency detail

None of them can fire for a service that does not publish the gauge. The estate
gets quieter, and quieter looks like healthier.

This is the alert that watches the watchers, and it exists because the metric it
watches is written as a side effect of something else happening.

## How it is supposed to work

`recordHealth()` in the shared observability kit sets the gauges. It runs inside
the `/health` handler, so the gauge is only as fresh as the last call to
`/health`. What calls it, in every environment, is the container's own Docker
healthcheck:

```yaml
healthcheck:
  test: ['CMD-SHELL', 'wget -qO- http://localhost:3000/health >/dev/null 2>&1']
  interval: 10s
```

That ten-second interval is load-bearing. Remove the healthcheck and the metric
goes stale, then absent.

## How to see

```promql
up{job=~"gpool-api|kini-api|notifications-api|trading-bot-control-plane"} == 1
  unless on (job) service_health_status
```

Directly, from the service:

```bash
curl -s http://<service>/metrics | grep service_health
curl -s http://<service>/health
```

## What to do

1. **Is there a healthcheck on the container?** `docker inspect <name> --format
   '{{json .Config.Healthcheck}}'`. If it is null, that is the bug.
2. **Does `/health` still respond?** If it 404s, the route moved — health lives
   at `/health`, off the API prefix, in every service.
3. **Does the handler still call `recordHealth`?** The vendored kit can drift;
   `bash platform-ops/scripts/verify-standards.sh` reports drift against the
   canonical copy.
4. **Was the service rebuilt after the kit was last synced?** A running image
   predating the change will not have the gauge — which is exactly how this
   alert first showed up.
