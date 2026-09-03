# RUM ingest rate-limiting

**Alert:** `RumIngestUnderAttack` (ticket)

## What fired

The RUM beacon endpoint has been rejecting more than one request per second for
rate-limiting, sustained over ten minutes.

## Whether it matters

Not to users — no product functionality depends on this endpoint. It matters
because of what it implies. `/rum` is public and unauthenticated by necessity:
browsers cannot hold a credential. Sustained rejection means something is
hitting it hard.

## How to see

```promql
sum by (job, reason) (rate(rum_rejected_total[5m]))
```

`reason` separates the cases: `rate_limited`, `payload_too_large`,
`invalid_schema`, `unknown_metric`. A spike in `invalid_schema` alongside
`rate_limited` reads as probing rather than a client bug.

## What to do

1. **A looping client first.** A UI bug that fires beacons in a render loop
   looks exactly like an attack and is far more likely. Check whether the source
   is one browser or many, and whether it started at a deploy.
2. **If it is external**, the rate limiter is already doing its job — nothing is
   reaching the metrics registry. Escalate to blocking at the ingress only if it
   is affecting the API's own capacity.
3. **Do not widen the limit** to make the alert stop.

## Why only this RUM metric has an alert

Everything else on this endpoint carries client-supplied labels, and an alert on
a client-supplied label is an alert an attacker can fire at will. `reason` is
assigned by the server from a fixed set, which is what makes it safe to alert
on. The same reasoning is why the ingest normalises route labels before they
reach Prometheus — an unbounded label is a cardinality bomb, and that path was
once traversable with `..`.
