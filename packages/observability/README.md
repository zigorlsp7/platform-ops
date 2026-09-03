# Observability kit

The canonical copy of the observability code every Node service runs. Vendored
into each repo by `scripts/sync-observability.sh`, and checked for drift by
`scripts/verify-standards.sh`.

**Edit here, never in a consuming repo.** Every synced file carries a
`DO NOT EDIT` header, and CI fails if a copy diverges.

## Why vendored rather than published

These are seven separate repositories across two GitHub owners, built by
Dockerfiles whose dependency stage copies only manifests. A private registry
would mean a token in every CI run and a build secret in every image, for four
files. The drift check buys the property that actually matters — copies cannot
silently diverge — without any of that.

If the estate grows past a handful of consumers, publish it properly; the
directory is already shaped like a package.

## What is in it

| file                         | for                                                   |
| ---------------------------- | ----------------------------------------------------- |
| `tracing.ts`                 | OTel bootstrap. Import **first**, before anything else |
| `json-logger.ts`             | structured logs carrying `traceId`, framework-free     |
| `metrics.registry.ts`        | the one prom-client registry                          |
| `http-metrics.middleware.ts` | request counter and duration histogram (Express)      |
| `nest.ts`                    | the NestJS adapter: `MetricsModule`                    |
| `index.ts`                   | the entry point                                       |

`tracing.ts`, `json-logger.ts` and `metrics.registry.ts` are framework-free.
Only `nest.ts` and `http-metrics.middleware.ts` assume Nest and Express.

## Contract

Configuration is read from the environment, following the OpenTelemetry spec:

| variable                      | meaning                                            | default                     |
| ----------------------------- | -------------------------------------------------- | --------------------------- |
| `OTEL_SERVICE_NAME`           | names the service in traces, logs, metrics, health | required                    |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | **base** URL; the kit appends `/v1/traces`         | `http://otel-collector:4318` |
| `OTEL_TRACES_ENABLED`         | `false` disables tracing entirely                  | enabled                     |

`OTEL_EXPORTER_OTLP_ENDPOINT` is the base URL, not the traces URL. This is what
the OTel spec says, what the Rust services already assume, and what gpool did —
notifications was the one treating it as a full path, which is why the two
stacks needed different values for the same variable name.
