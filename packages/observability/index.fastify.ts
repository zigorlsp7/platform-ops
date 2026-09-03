/**
 * The observability kit — Fastify flavour.
 *
 * `tracing` is deliberately NOT re-exported: it must be imported first, before
 * any instrumented module loads, so services import it directly as a side
 * effect (`import './observability/tracing';`) on the first line of `main.ts`.
 * Re-exporting it here would let it load late and instrument nothing.
 */
export { kafkaLogCreator, writeLogRecord } from './json-logger';
export type { LogLevel } from './json-logger';
export { registry } from './metrics.registry';
export { fastifyLoggerOptions, registerHttpMetrics } from './fastify';
export { allFlags, isEnabled, registerFlags } from './feature-flags';
export type { FlagDefinition, ResolvedFlag } from './feature-flags';
export { recordHealth } from './health-metrics';
