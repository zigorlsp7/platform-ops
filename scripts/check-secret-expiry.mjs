#!/usr/bin/env node
/**
 * Warns before a credential expires, rather than after.
 *
 * The estate's secrets live in OpenBao, and several of them are third-party
 * credentials with real expiry dates that nothing currently tracks: Google
 * OAuth client secrets, the Tolgee API key, TLS certificates, and the OpenBao
 * tokens themselves. Every one of them fails the same way — at 3am, in
 * production, with no warning.
 *
 * This reads expiry metadata that OpenBao already stores and reports anything
 * inside the warning window. It changes nothing; it is a report.
 *
 * Usage:
 *   node scripts/check-secret-expiry.mjs            # 30-day window
 *   node scripts/check-secret-expiry.mjs --days 60
 *   node scripts/check-secret-expiry.mjs --strict   # exit 1 on a finding
 *
 * Environment: OPENBAO_ADDR, OPENBAO_TOKEN.
 */

const args = process.argv.slice(2);
const days = Number(args[args.indexOf('--days') + 1]) || 30;
const strict = args.includes('--strict');

const addr = (process.env.OPENBAO_ADDR ?? 'http://127.0.0.1:8200').replace(/\/+$/, '');
const token = process.env.OPENBAO_TOKEN;

if (!token) {
  console.error('OPENBAO_TOKEN is required.');
  process.exit(2);
}

const horizon = Date.now() + days * 86_400_000;

async function bao(path) {
  const response = await fetch(`${addr}/v1/${path}`, {
    headers: { 'X-Vault-Token': token },
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) return null;
  return response.json();
}

const findings = [];

// 1. The token this script is using. A root or long-lived token that expires
//    unnoticed takes every deploy down with it.
const self = await bao('auth/token/lookup-self');
if (self?.data?.expire_time) {
  const expires = new Date(self.data.expire_time);
  if (expires.getTime() < horizon) {
    findings.push(`OpenBao token (${self.data.display_name ?? 'self'}) expires ${expires.toISOString()}`);
  }
}

// 2. Anything under kv/ carrying an explicit expiry. The convention is a
//    `expires_at` field in ISO 8601 beside the secret it describes.
const mounts = await bao('sys/mounts');
const kvMounts = Object.keys(mounts?.data ?? {}).filter((m) =>
  (mounts.data[m].type ?? '').startsWith('kv'),
);

for (const mount of kvMounts) {
  const base = mount.replace(/\/$/, '');
  const list = await bao(`${base}/metadata?list=true`);
  for (const key of list?.data?.keys ?? []) {
    const secret = await bao(`${base}/data/${key.replace(/\/$/, '')}`);
    const data = secret?.data?.data ?? {};
    for (const [field, value] of Object.entries(data)) {
      if (!/expir|expires_at|valid_until|not_after/i.test(field)) continue;
      const when = new Date(String(value));
      if (Number.isNaN(when.getTime())) continue;
      if (when.getTime() < horizon) {
        findings.push(`${base}/${key} → ${field} expires ${when.toISOString()}`);
      }
    }
  }
}

if (findings.length === 0) {
  console.log(`No secrets expire within ${days} days.`);
  process.exit(0);
}

console.warn(`Secrets expiring within ${days} days:`);
for (const f of findings) console.warn(`- ${f}`);
// A warning by default: an expiry that is still weeks away should not stop a
// deploy, but it should be impossible to miss.
process.exit(strict ? 1 : 0);
