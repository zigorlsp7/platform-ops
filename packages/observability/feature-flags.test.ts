import { beforeEach, describe, expect, it } from 'vitest';

import { allFlags, isEnabled, registerFlags } from './feature-flags';

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
});
