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

## 4. The shared kit

Every Node service runs the same observability code, vendored from
`platform-ops/packages/observability/` by `scripts/sync-observability.sh`.
**Edit it there, never in a consuming repo** — each synced file carries a
`DO NOT EDIT` header, and `verify-standards.sh` fails when a copy drifts.

| file                         | for                                               |
| ---------------------------- | ------------------------------------------------- |
| `tracing.ts`                 | OTel bootstrap; **import first**, see below       |
| `json-logger.ts`             | structured logs carrying `traceId`                |
| `metrics.registry.ts`        | the one prom-client registry                      |
| `http-metrics.middleware.ts` | request counter and duration histogram            |
| `nest.ts`                    | `ObservabilityModule` — `/metrics` + `JsonLogger` |

Vendored rather than published because these are seven repositories across two
GitHub owners, built by Dockerfiles whose dependency stage copies only
manifests. A private registry would mean a token in every CI run and a build
secret in every image, for five files. What matters is that copies cannot
silently diverge, and the drift check gives exactly that.

### The Rust half

The Rust services cannot vendor a TypeScript package, so `trading-bot/crates/observability`
is the equivalent: a workspace crate, not three copies, because copies drift and
the drift here is silent — the alerts simply stop covering a service.

It carries three things:

- **`HttpMetrics` + `track_http_metrics`**, an axum middleware emitting
  `http_requests_total` and `http_request_duration_seconds` under exactly the
  names and labels the Node middleware uses. The `route` label comes from
  axum's `MatchedPath`, and unmatched requests are labelled `unmatched` rather
  than by their raw path — otherwise a scanner probing random URLs creates a
  time series per probe.
- **`tracing_setup::init`**, the OTLP exporter and a log formatter producing the
  estate's JSON shape. `tracing_subscriber`'s own `.json()` writes
  `{"fields":{"message":...},"target":...}` with no `service` and no trace id,
  which would be a third log format in an estate that already agreed on one.
- **A span per HTTP request**, created by the same middleware.

That last one is the part that is easy to get wrong. **`tracing-opentelemetry`
exports spans, not events** — so wiring up the OTLP exporter without creating a
single span exports nothing at all, and nothing warns you. The three Rust
services had no `info_span!` or `#[instrument]` anywhere in them, so the
middleware is currently their whole tracing surface. Adding spans to the
interesting internals — backfill batches, order placement, backtest runs — is
where the next real value is.

### Import tracing first. Not second.

```ts
import './observability/tracing'; // FIRST. Nothing above this line.

import { NestFactory } from '@nestjs/core';
```

OpenTelemetry instruments by patching modules as they load. Anything required
before `tracing` is never patched, and it fails silently — you still get traces,
just thinner ones, which is far harder to notice than no traces at all.

This is not hypothetical. gpool had the import at the _bottom_ of its import
list. Its traces contained express middleware spans and nothing else: no
`pg.query`, no controller spans, because `pg` and `@nestjs/core` had already
loaded. notifications, which imported it first, produced all three. The two
services looked equally instrumented until someone compared span names.

### Configuration

| variable                      | meaning                                            | default                      |
| ----------------------------- | -------------------------------------------------- | ---------------------------- |
| `OTEL_SERVICE_NAME`           | names the service in traces, logs, metrics, health | required                     |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | **base** URL; the kit appends `/v1/traces`         | `http://otel-collector:4318` |
| `OTEL_TRACES_ENABLED`         | `false` disables tracing entirely                  | enabled                      |

`OTEL_EXPORTER_OTLP_ENDPOINT` is the base URL, per the OTel spec. notifications
used to treat it as the full traces URL, so the same variable name meant two
different things in one estate and each compose file carried a different value
to compensate. If a service ever exports to `.../v1/traces/v1/traces`, this is
why.

Tracing reads the environment directly rather than a config object, because it
must run before any DI container exists. A `tracingEnabled` field in a config
service is a field that cannot be honoured.

## 5. Health

**One endpoint per service: `GET /health`.** It probes dependencies and returns
200 only when the service can actually do its job.

```
GET /health   200 ok / 200 degraded / 503 error

{ "status": "ok",
  "service": "gpool-api",
  "components": { "db":    { "status": "up" },
                  "kafka": { "status": "up" } } }
```

`status` is one of three values, and the distinction is the point:

| `status`   | code | meaning                                                 |
| ---------- | ---- | ------------------------------------------------------- |
| `ok`       | 200  | every component up                                      |
| `degraded` | 200  | an **optional** component down — reduced, still serving |
| `error`    | 503  | a **required** component down — cannot do its job       |

Which components are required is a per-service judgement, and it is not
symmetric across the estate:

- **The database is always required.** Without it there is nothing to serve.
- **Kafka is required for the consumer, optional for the producers.**
  notifications consumes `notification.email.requested.v1`; a consumer that has
  dropped out of its group stops working silently, with mail piling up and
  nothing erroring anywhere, so its loss is a 503. gpool and kini only produce to
  that topic — a broker outage stops emails being queued but leaves every other
  request working, so it is a `degraded` 200. Failing the whole check there would
  take a mostly-working service out of rotation.

A component may also report `"unknown"`, which is not a failure: it means no
connection has been attempted yet. Reporting `down` at boot would be a lie.

What each service reports, and what it treats as fatal:

| service                          | components                                                                    | `degraded` when |
| -------------------------------- | ----------------------------------------------------------------------------- | --------------- |
| cv-web                           | —                                                                             | never           |
| gpool-api                        | `db`, `kafka`                                                                 | `kafka` down    |
| kini-api                         | `db`, `kafka`                                                                 | `kafka` down    |
| notifications-api                | `db`, `kafka`                                                                 | never           |
| trading-bot-control-plane        | `db`                                                                          | never           |
| trading-bot-market-data          | `runtimeConfig`, `kafkaProducer`, `kafkaConsumer`, `marketStream`, `database` | never           |
| trading-bot-execution            | `controlPlane`, `marketData`, `executionContext`, `exchange`                  | never           |
| trading-bot-research-backtesting | `controlPlane`, `historicalStore`                                             | never           |

Only gpool and kini have an optional dependency today. Everything else either
has none or cannot work without the ones it has, so its components are all
required and their loss is a 503.

Component values are objects, not bare strings — `{"status": "up"}` rather than
`"up"`. The nesting looks redundant for a bare up/down, and it is, until the day
a component needs a `latencyMs` or a `lastSeenAt` beside its status. Adding a
field to an object breaks no consumer; replacing a string with an object breaks
every one.

### Probing a broker you only produce to

A consumer knows the broker is gone: it crashes and reports it. A **producer**
does not. kafkajs gives a producer no way to ask "is the broker still there" —
its `DISCONNECT` event fires when _you_ disconnect, not when the broker
vanishes, and the connection pool reconnects lazily on the next send. Measured,
not assumed: with the broker stopped, a passive flag on gpool's producer read
`up` indefinitely.

So gpool and kini each run a small admin client on a 15-second timer, asking for
cluster metadata and recording whether it answered. Retries are off and the
timeouts are 3s: this is a probe, not a request that matters, and it must fail
fast rather than leave the health endpoint blocked behind a retry ladder. Health
reads the cached flag, so the endpoint stays instant.

Measured recovery after the broker came back: producers 25s, the consumer 75s
(its own retry backoff). Both self-heal without a restart.

`service` is the same string as `OTEL_SERVICE_NAME`, so health, metrics, traces
and logs all identify a service identically.

Keep the check under a second: one that times out under load turns a slow
service into a down one.

**Set the status code; do not throw.** Throwing routes the response through the
global exception filter, which replaces the body with its own error shape — so
the 503 arrives saying nothing about _which_ dependency failed, which is the only
part worth having. Use `@Res({ passthrough: true })` and `res.status(503)`.

**Health sits outside any global prefix, on every service including the Next.js
apps.** gpool excludes it alongside `metrics` in `setGlobalPrefix`; cv serves
`src/app/health/route.ts` rather than `src/app/api/health/`. A probe address that
varies by framework is a probe address someone will get wrong.

cv reports `components: {}` — it has no database and no broker, and a failed
Tolgee fetch already falls back to committed messages rather than failing the
page, so there is nothing whose loss it could honestly report.

### On collapsing liveness into health

The estate previously exposed `/health/liveness` (process up, no dependencies
touched) alongside `/health/readiness` (dependencies probed). One endpoint is
simpler and matches how these services are actually run, but the merge does lose
something worth writing down.

Liveness answers "restart me"; readiness answers "stop routing to me". Under
Docker Compose that distinction costs nothing: a failing healthcheck marks a
container unhealthy and Docker does **not** restart it. Under Kubernetes it
matters — a dependency-probing endpoint wired to `livenessProbe` turns a database
blip into a restart loop, and restarting a service never fixes its database.

**So: if any service moves to Kubernetes, point `readinessProbe` at `/health`
and give that service a separate dependency-free liveness path.** Until then the
single endpoint stands.

One live consequence today: `depends_on: service_healthy` blocks dependents while
a service is merely degraded, because Compose sees only healthy/unhealthy and a
`degraded` 200 reads as healthy — which is the behaviour we want, and the reason
producers return 200 rather than 503 when the broker is gone.

---

## 6. Real User Monitoring

Every UI in the estate runs the same RUM client from the kit: Core Web Vitals,
JavaScript errors, clicks, navigation, and frustration signals (rage clicks,
dead clicks, excessive scrolling). Each UI ingests its own beacons at
`POST /rum/events` and exposes the results on its own `/metrics`, so the four
web apps are Prometheus targets in their own right.

Ingesting locally rather than posting to a backend API is what makes this
uniform: cv and the operator console have no API of their own, and a UI that
reports its own experience needs no cross-service hop to do it.

### This endpoint is public, and that shapes everything

`POST /rum/events` cannot be authenticated. It is called by anonymous visitors,
before any login, often while the page is being unloaded. It is the only
unauthenticated write endpoint in the estate, so the protections live in the
handler:

| control               | what it stops                                             |
| --------------------- | --------------------------------------------------------- |
| Same-origin check     | a browser on another site posting on a visitor's behalf   |
| 64 KB body cap        | a single request tying up the process                     |
| 60 batches/min per IP | one client flooding the metrics                           |
| Allow-listed names    | **the important one — see below**                         |
| Route normalisation   | one time series per entity id                             |
| 204 empty response    | the endpoint working as an oracle for probing the filters |

**Every label value is chosen by the server, never by the caller.** Event names
are matched against an allow-list and anything else becomes `other`; paths are
collapsed to route patterns. Without that, `POST`ing a loop of random event
names creates unlimited Prometheus time series from the open internet — a
metrics endpoint is a write endpoint, and an unbounded label is a denial of
service with extra steps.

The rate limiter is a fixed window in process memory. In memory because this
must not add Redis to four web apps for a counter; it is a floor, not a
boundary, and a distributed flood still needs the reverse proxy in front of it.
`x-forwarded-for` is trusted only as far as its first entry, since the whole
header is caller-controlled when no proxy rewrites it.

### What is deliberately not collected

The original implementation in gpool sent, with every event: the full
`location.href` including the query string, the `userAgent`, the `id`,
`className` and visible `textContent` of whatever was clicked, the signed-in
user's id, and error stack traces. One call site passed an invitee's **email
address** as event metadata.

None of that survives. Query strings carry session tokens; button text is
user-visible copy that routinely contains names and email addresses; a user id
makes every event personally identifying for a signal that is aggregate by
nature; stack traces carry values from the code that threw. What is sent now is
a bounded enum and a number — which is exactly what makes an unauthenticated
ingest endpoint acceptable. There is nothing in the payload worth stealing.

Business events survive as names only: `trackEvent('Pool Created')`, with the
name declared in that app's `customInteractions` allow-list. Metadata is gone,
because it could never become a label and only ever shipped personal data.

`normalizePage` is the security-critical function here and has unit tests in
`packages/observability/rum-metrics.test.ts`. They exist because it shipped
broken: `..` matches the route-character test, so `/../../etc/passwd` reached a
label verbatim until a probe caught it.

---

## 7. Dashboard

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
