import assert from 'node:assert/strict';

import { trace } from '@opentelemetry/api';
import { afterEach, test, vi } from 'vitest';

import { kafkaLogCreator, writeLogRecord } from './json-logger';

const captured = { stdout: [] as string[], stderr: [] as string[] };

const capture = () => {
  captured.stdout.length = 0;
  captured.stderr.length = 0;
  vi.spyOn(process.stdout, 'write').mockImplementation((chunk) => {
    captured.stdout.push(String(chunk));
    return true;
  });
  vi.spyOn(process.stderr, 'write').mockImplementation((chunk) => {
    captured.stderr.push(String(chunk));
    return true;
  });
};

const onlyRecord = (lines: string[]): Record<string, unknown> => {
  assert.equal(lines.length, 1, `expected exactly one line, got ${lines.length}`);
  return JSON.parse(lines[0]) as Record<string, unknown>;
};

afterEach(() => {
  vi.restoreAllMocks();
  delete process.env.OTEL_SERVICE_NAME;
});

test('errors go to stderr, everything else to stdout, as one JSON line named after the service', () => {
  process.env.OTEL_SERVICE_NAME = 'gpool-api';
  capture();

  writeLogRecord('error', new Error('broker gone'), 'KafkaConsumer', 'Error: broker gone\n    at x');
  writeLogRecord('info', 'listening', 'Bootstrap');

  const error = onlyRecord(captured.stderr);
  assert.equal(error.level, 'error');
  assert.equal(error.service, 'gpool-api');
  assert.equal(error.message, 'broker gone');
  assert.equal(error.context, 'KafkaConsumer');
  assert.match(String(error.stack), /^Error: broker gone/);

  const info = onlyRecord(captured.stdout);
  assert.equal(info.level, 'info');
  assert.equal(info.message, 'listening');
  assert.equal('traceId' in info, false);
});

test('a line emitted inside an active span carries that span, so Loki can find the trace', () => {
  const traceId = 'a'.repeat(32);
  const spanId = 'b'.repeat(16);
  vi.spyOn(trace, 'getActiveSpan').mockReturnValue({
    spanContext: () => ({ traceId, spanId, traceFlags: 1 }),
  } as never);
  capture();

  writeLogRecord('warn', 'slow query');

  const record = onlyRecord(captured.stdout);
  assert.equal(record.traceId, traceId);
  assert.equal(record.spanId, spanId);
});

test('kafkajs lines take the shared shape, keeping their namespace and extra fields', () => {
  process.env.OTEL_SERVICE_NAME = 'notifications-api';
  capture();

  const log = kafkaLogCreator()(1);
  log({
    namespace: 'Connection',
    level: 1,
    label: 'ERROR',
    log: {
      message: 'Connection error: ECONNREFUSED',
      timestamp: '2026-09-07T10:00:00.000Z',
      logger: 'kafkajs',
      broker: 'platform-redpanda:9092',
    },
  });

  const record = onlyRecord(captured.stderr);
  assert.equal(record.level, 'error');
  assert.equal(record.service, 'notifications-api');
  assert.equal(record.context, 'kafkajs:Connection');
  assert.deepEqual(record.message, {
    message: 'Connection error: ECONNREFUSED',
    broker: 'platform-redpanda:9092',
  });
});
