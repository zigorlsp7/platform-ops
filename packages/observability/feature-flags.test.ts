import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  allFlags,
  connectRemoteFlags,
  disconnectRemoteFlags,
  isEnabled,
  registerFlags,
} from './feature-flags';

const remoteValues = new Map<string, boolean>();
let synchronized = true;
let lastConfig: Record<string, unknown> = {};

vi.mock('unleash-client', () => ({
  initialize: (config: Record<string, unknown>) => (
    (lastConfig = config),
    {
      isEnabled: (key: string, _context: unknown, fallback: boolean) =>
        remoteValues.has(key) ? remoteValues.get(key)! : fallback,
      on: (event: string, listener: () => void) => {
        if (event === (synchronized ? 'synchronized' : 'error')) listener();
      },
      destroy: () => undefined,
    }
  ),
}));

describe('feature flags', () => {
  beforeEach(() => {
    for (const key of Object.keys(process.env)) {
      if (key.startsWith('FLAG_')) delete process.env[key];
    }
  });

  it('uses the declared default when the environment says nothing', () => {
    registerFlags([{ key: 'newPayouts', description: 'x', defaultValue: false }]);
    expect(isEnabled('newPayouts')).toBe(false);
    expect(allFlags()[0].source).toBe('default');
  });

  it('lets the environment override the default', () => {
    process.env.FLAG_NEW_PAYOUTS = 'true';
    registerFlags([{ key: 'new-payouts', description: 'x', defaultValue: false }]);
    expect(isEnabled('new-payouts')).toBe(true);
    expect(allFlags().find((f) => f.key === 'new-payouts')?.source).toBe('environment');
  });

  it('accepts 1 and 0 as well as true and false', () => {
    process.env.FLAG_A = '1';
    process.env.FLAG_B = '0';
    registerFlags([
      { key: 'a', description: 'x', defaultValue: false },
      { key: 'b', description: 'x', defaultValue: true },
    ]);
    expect(isEnabled('a')).toBe(true);
    expect(isEnabled('b')).toBe(false);
  });

  it('ignores a value it cannot interpret rather than guessing', () => {
    process.env.FLAG_C = 'maybe';
    registerFlags([{ key: 'c', description: 'x', defaultValue: true }]);
    expect(isEnabled('c')).toBe(true);
    expect(allFlags().find((f) => f.key === 'c')?.source).toBe('default');
  });

  it('throws on an unregistered flag rather than returning false', () => {
    registerFlags([{ key: 'known', description: 'x', defaultValue: true }]);
    expect(() => isEnabled('typo')).toThrow(/Unknown feature flag/);
  });

  describe('with a remote source', () => {
    beforeEach(() => {
      remoteValues.clear();
      synchronized = true;
    });

    afterEach(() => {
      disconnectRemoteFlags();
    });

    const connect = () =>
      connectRemoteFlags({ url: 'http://unleash:4242', token: 't', appName: 'test' });

    it('lets the server override the declared value', async () => {
      registerFlags([{ key: 'cv-pdf-download', description: 'x', defaultValue: false }]);
      remoteValues.set('cv-pdf-download', true);

      expect(await connect()).toBe(true);
      expect(isEnabled('cv-pdf-download')).toBe(true);
    });

    it('falls back to the declared value for a flag the server has never heard of', async () => {
      registerFlags([{ key: 'only-local', description: 'x', defaultValue: true }]);

      await connect();

      expect(isEnabled('only-local')).toBe(true);
    });

    it('reports that a value came from the server', async () => {
      registerFlags([{ key: 'sourced', description: 'x', defaultValue: false }]);
      remoteValues.set('sourced', true);

      await connect();

      expect(allFlags().find((f) => f.key === 'sourced')?.source).toBe('remote');
    });

    it('still throws on an unregistered flag, so a typo cannot be answered by the server', async () => {
      registerFlags([{ key: 'declared', description: 'x', defaultValue: true }]);
      remoteValues.set('undeclared', true);

      await connect();

      expect(() => isEnabled('undeclared')).toThrow(/Unknown feature flag/);
    });

    it('resolves false when the server never synchronises, and keeps serving defaults', async () => {
      synchronized = false;
      registerFlags([{ key: 'degraded', description: 'x', defaultValue: true }]);

      expect(await connect()).toBe(false);
      expect(isEnabled('degraded')).toBe(true);
    });

    it('reports the flag set it caches to disk, so a restart without a server keeps the last values', async () => {
      registerFlags([{ key: 'cached', description: 'x', defaultValue: true }]);

      await connectRemoteFlags({
        url: 'http://unleash:4242',
        token: 't',
        appName: 'test',
        backupPath: '/tmp/flag-cache',
      });

      expect(lastConfig.backupPath).toBe('/tmp/flag-cache');
      expect(lastConfig.disableMetrics).toBe(false);
    });

    it('goes back to the declared values once disconnected', async () => {
      registerFlags([{ key: 'reverts', description: 'x', defaultValue: false }]);
      remoteValues.set('reverts', true);
      await connect();
      expect(isEnabled('reverts')).toBe(true);

      disconnectRemoteFlags();

      expect(isEnabled('reverts')).toBe(false);
    });
  });
});
