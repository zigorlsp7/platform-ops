# API High Error Rate

## Alert

`PlatformApiHighErrorRate`

## Meaning

The API 5xx ratio is above 2% over the last 5 minutes.

## Checks

1. Check API container logs in Grafana (Loki datasource).
2. Check recent deploy history and rollback if needed.
3. Check downstream dependencies (database, OpenBao, third-party APIs).

## Immediate Mitigation

1. Roll back to previous known-good app release.
2. Scale API replicas if saturation-related.
3. Disable faulty feature flags if applicable.
