#!/usr/bin/env node
/*
 * Applies the SQL files in supabase/migrations/ to the database, in order,
 * once each, and remembers which it has run in a `schema_migrations` table -
 * so a fresh database and an old one both end up at the same place.
 *
 *   cd scripts && npm install
 *   node migrate.js status      what's applied and what's waiting
 *   node migrate.js up          apply everything waiting (each file in its own transaction)
 *   node migrate.js baseline    record every file as already applied, WITHOUT running it
 *                               (for a database that was set up by hand up to now)
 *   node migrate.js baseline --to=0075   the same, but only up to and including that migration
 *   node migrate.js up --to=0070  stop after that migration
 *
 * DATABASE_URL comes from supabase/.env (or the environment). A migration that
 * fails is rolled back and nothing after it runs.
 *
 * Migrations are applied exactly as written, so they must not rely on being
 * re-run: write new ones as new files, never edit one that has been applied.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
require('dotenv').config({ path: path.join(__dirname, '..', 'supabase', '.env') });
const { Client } = require('pg');

const dir = path.join(__dirname, '..', 'supabase', 'migrations');

function files() {
  return fs.readdirSync(dir).filter((f) => /^\d+.*\.sql$/.test(f)).sort();
}

function checksum(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(path.join(dir, file))).digest('hex');
}

async function main() {
  const [command = 'status', ...rest] = process.argv.slice(2);
  const to = (rest.find((a) => a.startsWith('--to=')) || '').slice(5);
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is not set (supabase/.env)');

  // Keep certificate validation enabled: this tool carries database credentials
  // and executes schema changes, so encryption without server verification is
  // not sufficient.
  const client = new Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: true } });
  await client.connect();
  const lockName = 'fitness_application_schema_migrations';
  try {
    // Prevent two deploy jobs from applying the same pending migration at once.
    await client.query('select pg_advisory_lock(hashtext($1))', [lockName]);
    await client.query(`
      create table if not exists schema_migrations (
        version text primary key,
        checksum text not null,
        applied_at timestamptz not null default now()
      )`);
    const applied = new Map((await client.query('select version, checksum from schema_migrations')).rows.map((r) => [r.version, r.checksum]));
    const all = files();

    // A migration edited after it was applied means the source tree and database
    // no longer describe the same schema. Allow status to display the mismatch,
    // but never let deploy/baseline proceed until it is reconciled explicitly.
    const changedApplied = all.filter((file) =>
      applied.has(file) && applied.get(file) !== checksum(file) && applied.get(file) !== 'baseline'
    );
    for (const file of changedApplied) console.warn(`CHECKSUM MISMATCH  ${file} changed after it was applied`);
    if (changedApplied.length && command !== 'status') {
      throw new Error(`Refusing to ${command}: applied migrations changed (${changedApplied.join(', ')}). Reconcile the database and migration history first.`);
    }
    const waiting = all.filter((f) => !applied.has(f));

    if (command === 'status') {
      for (const file of all) console.log(`${applied.has(file) ? 'applied' : 'WAITING'}  ${file}`);
      console.log(`\n${applied.size} applied, ${waiting.length} waiting`);
    } else if (command === 'baseline') {
      const recorded = waiting.filter((f) => !to || f.slice(0, to.length) <= to);
      for (const file of recorded) {
        await client.query('insert into schema_migrations (version, checksum) values ($1, $2)', [file, checksum(file)]);
      }
      console.log(`Recorded ${recorded.length} migrations as applied (not run).`);
    } else if (command === 'up') {
      let count = 0;
      for (const file of waiting) {
        if (to && file.slice(0, to.length) > to) break;
        const sql = fs.readFileSync(path.join(dir, file), 'utf8');
        process.stdout.write(`applying ${file} ... `);
        try {
          await client.query('begin');
          await client.query(sql);
          await client.query('insert into schema_migrations (version, checksum) values ($1, $2)', [file, checksum(file)]);
          await client.query('commit');
          console.log('ok');
          count++;
        } catch (error) {
          await client.query('rollback');
          console.log('FAILED');
          throw new Error(`${file}: ${error.message}`);
        }
      }
      console.log(`${count} applied.`);
    } else {
      throw new Error(`unknown command "${command}" (status, up, baseline)`);
    }
  } finally {
    await client.query('select pg_advisory_unlock(hashtext($1))', [lockName]).catch(() => {});
    await client.end();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
