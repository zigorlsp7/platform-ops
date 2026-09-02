# Operations

## Backups

**Nothing in the estate is backed up.** Not Postgres, not the OpenBao raft store,
not the Tolgee volume. The only `.backup` files present are Terraform state.

A single EC2 host holds every database, every secret and every translation. The
required baseline:

- `pg_dump` per database, nightly, to S3 with lifecycle expiry
- `bao operator raft snapshot save`, nightly
- Tolgee volume archive, nightly
- **A restore, performed once, before calling any of it done**

An untested backup is a hypothesis. The restore rehearsal is the part that turns
it into a fact, and it is the step most likely to be skipped.

## Graceful shutdown

Every service handles `SIGTERM` and finishes in-flight work before exiting. In
Nest that is `app.enableShutdownHooks()`; `notifications` is the only service
that calls it. The others drop live requests on every deploy.

## Alerting

Alert on **symptoms users feel**, not on causes. Three rules currently exist for
the entire estate, and two of them fire on a generic `platform_api` job.

Required per service:

- availability, from a `/health` that actually probes its dependencies
- error ratio and p95 latency against a stated SLO
- one alert on its own domain — a queue that stops draining, a consumer that
  stops consuming

Required for the platform:

- host disk (a full Docker disk has already taken Tolgee down once)
- Kafka consumer lag
- dead-letter growth — `notifications` writes dead letters and nothing watches
  the table
- certificate expiry — Caddy renews automatically and fails silently
- OpenBao sealed

Alertmanager already has Slack, PagerDuty and email receivers with severity
routing. The routing is well ahead of the rules feeding it.

## SLOs

Each product states one availability and one latency objective, written down with
the reasoning. Alerts then use **multi-window burn rate** against those
objectives rather than raw thresholds.

Until an SLO exists, every threshold is a guess, and a guessed threshold trains
people to ignore the alert.

## Runbooks

Every alert links to a runbook from its annotation. A runbook states what the
alert means, what to check first, and what to do — not what the metric is.

An alert with no runbook is a notification.

## Rollback

Images are tagged in ECR, so rollback is possible. There is no script and no
document describing it, which means the procedure only exists in whoever's head
last deployed. Write it down and rehearse it with the backup restore.
