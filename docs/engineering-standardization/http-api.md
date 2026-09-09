# HTTP API

Five services answer HTTP: `gpool`, `kini` and `notifications` on NestJS,
`trading-bot`'s control-plane on Fastify, and `cv`'s Next.js route handlers.
They were built at different times and agree on almost nothing at the edge —
four error bodies, two naming schemes, one versioned service and four
unversioned ones.

This page is the contract they converge on.

## Error body

**RFC 9457 Problem Details**, sent as `application/problem+json`:

```json
{
  "type": "https://zigordev.com/problems/pool-not-found",
  "title": "Pool not found",
  "status": 404,
  "detail": "No pool exists with id 7f3a1c02.",
  "instance": "/pools/7f3a1c02",
  "code": "POOL.NOT_FOUND",
  "params": { "poolId": "7f3a1c02" }
}
```

`type`, `title`, `status`, `detail` and `instance` are the RFC's. Two
extensions carry what the estate already needs:

| field    | for                                                                     |
| -------- | ----------------------------------------------------------------------- |
| `code`   | the key a client translates, stable across wording changes              |
| `params` | the values that key interpolates, so the client formats, not the server |

`kini` already sends `code` and `params` and its web client already reads them;
that is why they survive into the standard rather than being replaced by
`detail`. `detail` is for a human reading a log or a response body, never for a
user-facing string.

`title` is the same for every response with a given `code`. `detail` may name
specifics. Neither is translated server-side.

### What goes away

`gpool` sends `timestamp`, `path` and `method`. All three are already in the
structured log line for the same request, keyed by `traceId`, and none of them
help a client decide anything. They move out of the body.

A 5xx body carries `type`, `title`, `status` and `code` only. No `detail`, no
stack, no message from the underlying exception — that is how an ORM error text
reaches a browser.

## Resources and paths

Plural nouns, kebab-case, nested under the resource that owns them:

```
/pools
/pools/{poolId}
/pools/{poolId}/matches
/pools/{poolId}/matches/{matchId}
```

`gpool` is already shaped this way. `kini` is not: `fut-pool`,
`fut-pool-match` and `logs` are singular, unnested, or both.

A state change that is not a create, replace or delete stays a `POST` on a
sub-path of the resource it changes:

```
POST /pools/{poolId}/request-access
POST /pools/{poolId}/matches/{matchId}/predict
POST /available-pools/{availablePoolId}/sync
```

This is what both APIs already do, and it is the honest shape: "request access"
is not a field you can PUT. The rule is only that the verb hangs off the
resource it acts on, so it can be authorised the same way as everything else
under that path.

`kini`'s `POST /available-pools/team-pools/{poolId}/check-results` breaks that:
the resource being checked is a team pool, not an available pool. It moves to
`POST /fut-pools/{poolId}/check-results`.

## Status codes

| verb            | success | notes                                     |
| --------------- | ------- | ----------------------------------------- |
| `GET`           | 200     |                                           |
| `POST` creating | 201     | with a `Location` header                  |
| `POST` acting   | 200     | 202 if the work continues after the reply |
| `PUT` / `PATCH` | 200     | the updated representation                |
| `DELETE`        | 204     | no body                                   |

Every route states its codes explicitly. In the Nest apps this means
`@HttpCode`, because Nest returns 201 from every `POST` by default: today
`POST /pools/{poolId}/request-access` answers 201 while its own
`@ApiResponse` says 200, and the generated client is built from the
annotation rather than the behaviour. `trading-bot` already does this right,
returning 201 on create and 204 on delete from the route schema.

## Versioning

No URL version on `gpool`, `kini` or `notifications`. Each has exactly one
client, in the same repository, and CI regenerates that client from the running
service's OpenAPI document and fails on drift. A version segment on a path that
cannot skew buys nothing.

`trading-bot`'s control-plane keeps `/v1/`. Three Rust services call it across a
network, deploy separately, and cannot be regenerated in lockstep.

The rule: version a path when something you do not deploy together calls it.

## Health and metrics

`GET /health` and `GET /metrics` at the root of every service, outside any
prefix, unauthenticated, never versioned.

Health answers with the shape four services already send:

```json
{
  "status": "ok",
  "service": "gpool-api",
  "components": { "db": { "status": "up" }, "kafka": { "status": "up" } }
}
```

`status` is `ok`, `degraded` or `error`. `components` maps a dependency name to
`{"status": "up" | "down" | "unknown"}`; `unknown` means no connection has been
attempted yet, which is not a failure. The response is 200 unless the service
cannot serve traffic at all, and 503 when it cannot.

This is a description, not a proposal: `gpool`, `kini`, `notifications` and
`trading-bot` all send it today, and `cv` sends the same keys with an empty
`components`. The only work is keeping it that way.

`/metrics` is the Prometheus text format from the vendored observability kit.

## Pagination

Nothing in the estate paginates today. When a collection first needs it, it is
opaque cursors, not offsets:

```
GET /pools?limit=50&cursor=eyJpZCI6...
```

```json
{ "items": [], "nextCursor": "eyJpZCI6..." }
```

`nextCursor` is absent on the last page. `limit` defaults to 50 and is capped at 200. Offsets are excluded because they skip and repeat rows when the underlying
set changes between requests, which is exactly what a ranking or a match list
does.

## The document is the contract

Every Nest service exposes OpenAPI at `/docs-json`, and `gpool` and `kini`
regenerate their web client from it in CI and fail on drift. That check is what
makes the rest of this page enforceable: a route that lies about its status
codes or its error shape produces a client that lies the same way, and the diff
shows up in the pull request.

`notifications` has no client and no Swagger module; it stays that way while it
has no HTTP surface beyond `/health` and `/metrics`.
