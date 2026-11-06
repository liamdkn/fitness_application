#!/usr/bin/env node
/*
 * Looks at what the Ultrahuman API really returns for YOUR ring, so the app can be built on
 * the real shape rather than on third-party write-ups.
 *
 * Setup (once):
 *   1. Ultrahuman developer portal (vision.ultrahuman.com/developer-docs) -> create a Personal API token.
 *   2. Put it in scripts/.ultrahuman.env as one line:   ULTRAHUMAN_TOKEN=your-token
 *      (that file is git-ignored by the *.env rule; never paste the token into chat)
 *
 * Run:
 *   node ultrahuman_probe.js                      today, shape only (field names and types)
 *   node ultrahuman_probe.js --values             today, with the values
 *   node ultrahuman_probe.js --date=2026-11-04 --values
 *   node ultrahuman_probe.js --days=7 --values    the last 7 days (the API's maximum range)
 *
 * It only reads. The token is sent to partner.ultrahuman.com and is never printed.
 */
const fs = require('fs');
const path = require('path');

const BASE = 'https://partner.ultrahuman.com/api/v1/partner/daily_metrics';

function loadToken() {
  if (process.env.ULTRAHUMAN_TOKEN) return process.env.ULTRAHUMAN_TOKEN.trim();
  const file = path.join(__dirname, '.ultrahuman.env');
  if (fs.existsSync(file)) {
    const line = fs.readFileSync(file, 'utf8').split('\n').find((l) => l.startsWith('ULTRAHUMAN_TOKEN='));
    if (line) return line.slice('ULTRAHUMAN_TOKEN='.length).trim().replace(/^["']|["']$/g, '');
  }
  return null;
}

const arg = (name) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split('=')[1] : null;
};
const showValues = process.argv.includes('--values');

// Prints every field path with its type (and the value, with --values), arrays summarised by their first item.
function walk(value, prefix = '') {
  if (Array.isArray(value)) {
    console.log(`${prefix || '(root)'}: array(${value.length})`);
    if (value.length) walk(value[0], `${prefix}[0]`);
  } else if (value && typeof value === 'object') {
    for (const [key, inner] of Object.entries(value)) walk(inner, prefix ? `${prefix}.${key}` : key);
  } else {
    const shown = showValues ? `  = ${JSON.stringify(value)}` : '';
    console.log(`${prefix}: ${value === null ? 'null' : typeof value}${shown}`);
  }
}

async function call(token, query, scheme) {
  const response = await fetch(`${BASE}?${query}`, {
    headers: { Authorization: scheme === 'bearer' ? `Bearer ${token}` : token, Accept: 'application/json' },
  });
  const text = await response.text();
  return { status: response.status, text };
}

(async () => {
  const token = loadToken();
  if (!token) {
    console.error('No token. Put ULTRAHUMAN_TOKEN=... in scripts/.ultrahuman.env (see the top of this file).');
    process.exit(1);
  }

  let query;
  const days = Number(arg('days'));
  if (days > 0) {
    const end = Math.floor(Date.now() / 1000);
    query = `start_epoch=${end - Math.min(days, 7) * 86400}&end_epoch=${end}`;
  } else {
    const date = arg('date') || new Date().toISOString().slice(0, 10);
    query = `date=${date}`;
  }

  // The docs say "Authorization header" without saying if it is the bare token or Bearer: try both.
  let result = await call(token, query, 'raw');
  let scheme = 'the bare token';
  if (result.status === 401 || result.status === 403) {
    result = await call(token, query, 'bearer');
    scheme = 'Bearer <token>';
  }
  console.log(`HTTP ${result.status} (Authorization: ${scheme})\n`);

  let json;
  try {
    json = JSON.parse(result.text);
  } catch {
    console.log(result.text.slice(0, 600));
    process.exit(result.status === 200 ? 0 : 1);
  }
  walk(json);
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
