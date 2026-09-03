# Service degraded

**Alert:** `ServiceDegraded` (ticket)

## What fired

`service_health_status == 1` for fifteen minutes. The service is serving
requests normally, with an optional dependency down.

Today that means one thing in practice: **gpool or kini cannot reach the broker,
so outbound email is not being queued.** Invitations, password resets and
notifications are being accepted by the API and silently not delivered.

## Whether it matters

More than it looks. Nothing errors. Users see success messages. The mail simply
never arrives, and the first report comes from a person wondering why they never
got their invite — which is why this needs an alert rather than a dashboard
panel nobody is looking at.

It is a ticket rather than a page because the product still works and the
messages are recoverable once the broker returns.

## How to see

```promql
service_component_up{component="kafka"} == 0
```

The health endpoint agrees:

```bash
curl -s https://<host>/health | jq '.components'
```

## What to do

1. Check the broker — [redpanda-down.md](redpanda-down.md).
2. Once it is back, confirm the producers reconnected: `service_health_status`
   should return to 2 within about fifteen seconds, which is the probe interval.
3. **Check what was lost.** Messages produced while the broker was unreachable
   were not queued anywhere. If the outage was long, the affected users need
   their invitations resending by hand.

## Known issue

`trading-bot-market-data` does not rejoin its consumer group after a broker
restart and has to be restarted manually. That is tracked separately; if this
alert follows a Redpanda restart, check that service explicitly.
