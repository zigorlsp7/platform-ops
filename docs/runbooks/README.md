# Runbooks

One file per alert. Every `runbook_url` in
[`docker/prometheus/alerts.yml`](../../docker/prometheus/alerts.yml) resolves to
a file here — that is checked by `scripts/verify-standards.sh`, because a
runbook link that 404s is worse than no link at all.

A runbook is written for the version of you that is reading it at an
inconvenient moment. Each one answers four questions in the same order:

1. **What fired** — the condition, in plain terms.
2. **Whether it matters** — what a user is experiencing right now, if anything.
3. **How to see** — the exact query, command, or dashboard.
4. **What to do** — the most likely causes, in the order they are usually true.

Nothing here is a decision tree. When the answer is "it depends", the runbook
says what it depends on.

| Alert | Runbook |
| --- | --- |
| `AvailabilityBudget*` | [availability-burn.md](availability-burn.md) |
| `LatencyBudget*` | [latency-burn.md](latency-burn.md) |
| `ServiceDown` | [service-down.md](service-down.md) |
| `ServiceUnhealthy` | [service-unhealthy.md](service-unhealthy.md) |
| `ServiceDegraded` | [service-degraded.md](service-degraded.md) |
| `ComponentDown` | [component-down.md](component-down.md) |
| `HostDisk*`, `HostFilesystemWillFillIn24h` | [host-disk.md](host-disk.md) |
| `HostMemoryPressure` | [host-memory.md](host-memory.md) |
| `KafkaConsumerLagGrowing` | [kafka-lag.md](kafka-lag.md) |
| `DeadLetterQueueGrowing` | [dead-letters.md](dead-letters.md) |
| `RedpandaDown` | [redpanda-down.md](redpanda-down.md) |
| `CoreWebVitalsRegressed` | [web-vitals.md](web-vitals.md) |
| `RumIngestUnderAttack` | [rum-ingest.md](rum-ingest.md) |

## Where to look

| Thing | Local | Prod |
| --- | --- | --- |
| Prometheus | <http://localhost:9090> | via the ops ingress |
| Alertmanager | <http://localhost:9093> | not exposed; use email |
| Grafana | <http://localhost:3001> | `OPS_GRAFANA_DOMAIN` |
| Jaeger | <http://localhost:16686> | not exposed |

Locally, alerts go nowhere by design — `config.local.yml` routes everything to a
null receiver. Alertmanager's own UI is the local delivery channel.
