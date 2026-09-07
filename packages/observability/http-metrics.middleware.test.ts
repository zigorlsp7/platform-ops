import assert from 'node:assert/strict';

import { test } from 'vitest';

import { httpMetricsMiddleware } from './http-metrics.middleware';
import { registry } from './metrics.registry';

const request = (method: string, path: string, routePattern?: string, statusCode = 200): void => {
  const req = {
    method,
    path,
    baseUrl: '',
    route: routePattern ? { path: routePattern } : undefined,
  };
  const res = {
    statusCode,
    on(event: string, listener: () => void) {
      if (event === 'finish') listener();
    },
  };
  httpMetricsMiddleware(req as never, res as never, () => {});
};

const seriesFor = async (route: string) => {
  const metric = registry.getSingleMetric('http_requests_total');
  assert.ok(metric, 'http_requests_total is registered');
  const { values } = await metric.get();
  return values.filter((value) => value.labels.route === route);
};

test('a matched route is labelled by its pattern, never by the resolved path', async () => {
  request('GET', '/pools/42', '/pools/:id');
  request('GET', '/pools/43', '/pools/:id');

  const byPattern = await seriesFor('/pools/:id');
  assert.equal(byPattern.length, 1);
  assert.equal(byPattern[0].value, 2);
  assert.equal((await seriesFor('/pools/42')).length, 0);
});

test('paths that matched no route share one label, so a scanner cannot mint a series per URL', async () => {
  request('GET', '/wp-admin/setup-config.php', undefined, 404);
  request('GET', '/.env', undefined, 404);
  request('GET', '/cgi-bin/luci', undefined, 404);

  const unmatched = await seriesFor('unmatched');
  assert.equal(unmatched.length, 1);
  assert.equal(unmatched[0].value, 3);
  assert.equal((await seriesFor('/.env')).length, 0);
});
