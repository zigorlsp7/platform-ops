# Availability budget burning

**Alerts:** `AvailabilityBudgetBurningFast` (page) ·
`AvailabilityBudgetBurning` (page) · `AvailabilityBudgetErodingSlowly` (ticket)

## What fired

The service is returning 5xx responses fast enough that, at this rate, it will
spend its entire 30-day error budget early. The SLO is 99.5% of requests
succeeding, so the budget is 0.5% — roughly 3.5 hours of total failure per
month, or a small constant trickle.

Three thresholds, three meanings:

| Alert | Burn rate | Budget gone in | Reaction |
| --- | --- | --- | --- |
| `…BurningFast` | 14.4x | ~2 days | Now |
| `…Burning` | 6x | ~5 days | Today |
| `…ErodingSlowly` | 3x | ~10 days | This week |

Each one requires a long window *and* a short window to be over the line, so a
firing alert means it is still happening — not that it happened earlier.

## Whether it matters

Yes, and to real people: a 5xx is a request that failed. Which people depends on
`job` — `gpool-api` is signup and booking, `notifications-api` is outbound mail,
`trading-bot-execution` is orders.

## How to see

Current error ratio per service:

```promql
1 - slo:availability:ratio_rate5m
```

Which endpoints, and which status codes:

```promql
topk(10, sum by (job, route, status) (rate(http_requests_total{status=~"5.."}[15m])))
```

Then a trace for one of them. Jaeger, filter by service and `error=true`; the
span with the exception on it names the failing call.

## What to do

Most often, in this order:

1. **A dependency, not the service.** Check `service_component_up` — a database
   or broker that went away shows up here first. If it is down, the alert you
   want is that one, and this alert resolves when it does.
2. **A deploy.** Compare the start of the burn against the last release. If they
   line up, roll back first and diagnose after.
3. **One endpoint, not the service.** The `topk` above says so immediately.
   A single failing route with a small share of traffic can still burn 14x if
   overall traffic is low; the burn rate is a ratio, and quiet services have
   noisy ratios.
4. **Genuinely more load than capacity.** `platform_api:http_rps:rate30s` against
   its usual shape.

If the cause is understood and the fix is not immediate, silence the alert in
Alertmanager with an end time — never indefinitely.

## Note on quiet services

Every burn alert carries a traffic gate: `slo:traffic:rate<window> > 0.05`,
roughly three requests a minute. Below that, the alert cannot fire.

This matters because a ratio over a handful of requests is an anecdote, not a
measurement — one 5xx out of three requests is a 33% error rate and a 66x burn.
A completely idle service produces no series at all: the SLI divides zero by
zero, which is NaN, and Prometheus drops NaN from comparisons.

So a quiet service is not being watched for availability, and that is
deliberate. What still covers it is [service-down.md](service-down.md) and
[service-unhealthy.md](service-unhealthy.md), which do not depend on traffic.
