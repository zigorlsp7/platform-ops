# The observability contract

Every deployable implements all five of these. They are a contract because the
platform is built around them: Prometheus scrapes a path, Alloy parses a log
shape, Jaeger receives a service name. A service that skips one is invisible in
that dimension, and the platform cannot tell the difference between "healthy"
and "not reporting".

Today the platform scrapes **two of seven** services.

---

## 1. Traces

OTLP over HTTP to the shared collector. Bootstrapped before anything else
imports, so instrumentation can patch the modules it wraps.

Reference implementation: `notifications/apps/api/src/instrumentation.ts`.

```ts
resource: { [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME }
traceExporter: new OTLPTraceExporter({ url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT })
```

Instrument what the service actually uses — HTTP and the framework always, plus
`pg` if it has a database and `kafkajs` if it consumes events. `notifications`
loads http, express, nest, pg and kafkajs; `gpool` uses the generic
auto-instrumentation bundle, which is broader and less precise.

**`OTEL_SERVICE_NAME` is `<repo>-<app>`** — `gpool-api`, `notifications-api`,
`cv-web`. This is the same string as the Prometheus job name and the Grafana
dashboard title. One name, three tools.

Setting the env vars is not instrumentation. `cv`'s compose file exports
`OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_SERVICE_NAME` while the repository has no
`@opentelemetry` package installed at all. Nothing sends a span.

---

## 2. Metrics

Prometheus text format on `GET /metrics`, unauthenticated on the private network.

Reference implementation: `gpool/apps/api/src/common/metrics/`.

**Every HTTP service exposes these two, with exactly these names and labels:**

```
http_requests_total              Counter    [method, route, status]
http_request_duration_seconds    Histogram  [method, route, status]
  buckets: 0.005 0.01 0.025 0.05 0.1 0.25 0.5 1 2 5
```

`route` is the **route pattern**, never the resolved path — `/pools/:id`, not
`/pools/8f2a`. A label whose cardinality grows with traffic will eventually take
Prometheus down.

Plus `collectDefaultMetrics()` for process and runtime gauges.

**Business metrics** are named `<domain>_<noun>_<verb>_total`, and every service
should have at least one. RED metrics tell you the API is healthy; they cannot
tell you nobody has joined a pool in six hours. `notifications` counts
deliveries. No other service counts anything about its own domain.

---

## 3. Logs

One JSON object per line, to stdout. Alloy tails the container and ships it to
Loki; nothing else is required of the application.

Reference implementation: `notifications/apps/api/src/common/json-logger.ts`.

**The record shape is fixed:**

| Field       | Always         | Notes                                  |
| ----------- | -------------- | -------------------------------------- |
| `timestamp` | yes            | ISO 8601                               |
| `level`     | yes            | `log` `error` `warn` `debug` `verbose` |
| `service`   | yes            | same value as `OTEL_SERVICE_NAME`      |
| `message`   | yes            |                                        |
| `context`   | when known     | the emitting class or module           |
| `traceId`   | when in a span |                                        |
| `spanId`    | when in a span |                                        |
| `stack`     | on errors      |                                        |

`error` goes to stderr; everything else to stdout.

**`traceId` is the field that makes the platform cohere.** With it, a slow span
in Jaeger and the log lines that produced it are one query apart. Without it,
Loki and Jaeger are two tools that happen to be installed on the same host.
`notifications` already reads the active span context and emits both ids — it is
the only service that does, and it is the pattern to copy verbatim.

Three of five services emit unstructured text through `console.log`. Loki
faithfully collects all of it and can tell you almost nothing about it.

---

## 4. Health

`GET /health` **probes dependencies**. It returns 200 only when the service can
actually do its job.

No repository currently does this. Every `/health` in the estate is a static 200,
which means `up{job="gpool-api"} == 0` — the estate's only availability alert —
catches a dead process and nothing else. A service whose database is gone reports
healthy and pages nobody.

Use `@nestjs/terminus`. Probe the database, the broker, and any upstream the
service cannot function without. Keep it under a second: a health check that
times out under load turns a slow service into a down one.

Compose `healthcheck:` blocks and the Prometheus `up` alert both point at this
endpoint, so its honesty is what makes them meaningful.

---

## 5. Dashboard

One Grafana dashboard per service, provisioned from a file in
`platform-ops/docker/grafana/provisioning/dashboards/`, named
`<service>-overview.json`.

Generated from one template so services stay comparable — request rate, error
ratio, p95 latency, and the service's own business metric. Two dashboards
currently exist for seven services.

---

## Frontend services

A browser application implements the same contract plus:

- **Core Web Vitals as metrics.** LCP, CLS, **INP** and TTFB, posted to the app's
  own endpoint and re-exported as Prometheus histograms so they can be alerted
  on. `gpool` collects these already but stores them privately, so they can
  never fire an alert. It also still measures **FID**, which Google replaced with
  INP in March 2024.
- **A browser error path.** An uncaught exception in a UI is currently invisible
  everywhere. It should reach the same place a server error does.
