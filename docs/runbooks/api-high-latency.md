# API High Latency (P95)

## Alert

`PlatformApiHighLatencyP95`

## Meaning

API p95 latency is above 300ms over the last 5 minutes.

## Checks

1. Check request/DB timing in traces (Grafana traces view).
2. Check DB saturation (connections, slow queries, CPU/IO).
3. Check upstream/downstream API latency dependencies.

## Immediate Mitigation

1. Roll back recent performance-impacting changes.
2. Increase API capacity if CPU-bound.
3. Reduce expensive query paths / enable degraded mode.
