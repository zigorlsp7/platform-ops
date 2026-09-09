# Engineering standardisation

The rules every zigordev repository follows, and the record of who follows them
yet.

## Why this exists

Four products, three shared repositories, and no two of them were built the same
way. The estate's problem was never engineering quality — it was propagation. A
hard problem would get solved properly in one repository and stay there:
structured logging in `notifications`, contract-drift detection in `gpool`, RUM
in `gpool`, a build-time PDF in `cv`. Meanwhile `trading-bot` had no CI at all.

This directory existed as an empty folder for over a month. That absence _was_
the root cause: without a written standard, every repository solves each problem
locally and the solutions diverge again within a quarter.

## How to use it

Each document states rules that are **checkable** — a rule you cannot verify from
a terminal is a preference, not a standard. Where a rule codifies something that
already works somewhere, it names that implementation rather than inventing a new
one.

| Document                                   | Covers                                                |
| ------------------------------------------ | ----------------------------------------------------- |
| [repository-shape.md](repository-shape.md) | Folder layout, required files, npm script surface     |
| [conventions.md](conventions.md)           | Node version, test runner, commits, code layout       |
| [ci-pipeline.md](ci-pipeline.md)           | The jobs every repository runs, and what each gates   |
| [observability.md](observability.md)       | Traces, metrics, logs, health — the contract          |
| [http-api.md](http-api.md)                 | Error body, paths, status codes, versioning, health   |
| [security.md](security.md)                 | Secrets, scanning, headers, dependencies              |
| [operations.md](operations.md)             | Backups, shutdown, alerting, runbooks                 |
| [adoption.md](adoption.md)                 | Where each repository stands, and the migration order |

## The rule about rules

A standard nobody can meet is worse than none, because it teaches people to
ignore the document. Every rule here is either already met by at least one
repository, or is small enough to adopt in under a day. Anything larger belongs
in the phased plan in [adoption.md](adoption.md), not in a rule.
