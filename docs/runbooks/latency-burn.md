# Latency budget burning

**Alerts:** `LatencyBudgetBurningFast` (page) · `LatencyBudgetEroding` (ticket)

## What fired

More than 5% of requests are taking longer than 500ms, and have been for at
least an hour. The SLO is "95% of requests inside 500ms"; the fast variant means
the miss rate is fourteen times what the budget allows.

The indicator is the fraction of requests inside the `le="0.5"` histogram
bucket, not a p95 quantile. Quantiles cannot be averaged across time windows —
a p95-of-p95s is not a p95 of anything — and the multi-window comparison this
alert depends on needs a value that can be.

## Whether it matters

Usually less than an availability alert, and occasionally more: a slow API that
holds connections open eventually becomes an unavailable one when the pool is
exhausted. If both alerts are firing for the same service, treat latency as the
cause and availability as the symptom.

## How to see

Where the time is going, by endpoint:

```promql
histogram_quantile(0.95, sum by (job, route, le) (rate(http_request_duration_seconds_bucket[10m])))
```

Then Jaeger, sorted by duration, for the slowest span in a slow trace. This is
the thing tracing is for; the answer is usually a single database call.

## What to do

1. **A query that lost its index**, or one that grew past it. The slow span is a
   `pg.query`; take its statement to `EXPLAIN ANALYZE`.
2. **A dependency that got slower** rather than failing — an upstream API, the
   broker, an OpenBao read on a hot path.
3. **N+1**. The trace shows it as a fan of near-identical sibling spans.
4. **Host pressure.** If `HostMemoryPressure` is also firing, start there:
   everything is slow when the host is swapping.

## Note

500ms is a single target for every service in the estate. It is generous for
`cv-web`, which serves static pages, and tight for anything that does real work
per request. The reasoning for one number rather than per-service targets is in
[operations.md](../engineering-standardization/operations.md); revisit it when a
service is alerting on latency that is normal for what it does.
