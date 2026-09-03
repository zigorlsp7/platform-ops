import { defineConfig } from 'vitest/config';

/**
 * Vitest, not `node:test` + tsx — one runner across the estate.
 *
 * Vitest transpiles TypeScript itself, so the `tsx` dependency that existed
 * purely to let `node --test` read a `.ts` file is gone.
 */
export default defineConfig({
  test: {
    environment: 'node',
    include: ['packages/**/*.test.ts'],
  },
});
