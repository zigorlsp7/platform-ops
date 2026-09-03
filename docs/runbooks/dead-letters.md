# Dead-lettered notifications

**Alert:** `DeadLetterQueueGrowing` (ticket)

## What fired

`notifications_dlq_total` increased in the last hour. One or more messages were
retried, kept failing, and were moved to the dead-letter topic.

## Whether it matters

Every dead letter is an email a person expected and did not receive: an
invitation, a password reset, a booking confirmation. The count is small and the
consequence is not.

## How to see

How many, and how recently:

```promql
increase(notifications_dlq_total[6h])
```

What they were — read the dead-letter topic on the broker:

```bash
docker exec -it platform-redpanda rpk topic consume notification.email.dlq --num 20
```

The reason is in the service logs at the time of the failure; the trace ID in
the log line opens the full path in Jaeger.

## What to do

1. **Read one.** The failures are nearly always the same failure repeated, and
   one message tells you which.
2. **Common causes** — the SMTP relay rejecting the recipient, a malformed
   payload from a producer that changed shape without a contract change, or a
   template referencing a field that is not there.
3. **Fix the cause, then replay.** Messages in the DLQ are not automatically
   retried; they stay until something replays them deliberately.
4. **Tell the affected people** if the failure window was long. They are waiting
   for mail that is not coming.
