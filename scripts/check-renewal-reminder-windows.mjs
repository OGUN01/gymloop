import { readFileSync, writeFileSync } from 'node:fs';

const migrationPath = 'supabase/migrations/20260915100007_phase6_comms.sql';
const constants = readFileSync('packages/shared/src/config/constants.ts', 'utf8');
const migration = readFileSync(migrationPath, 'utf8');
const block = constants.match(/RENEWAL_REMINDER_WINDOWS\s*=\s*\[([\s\S]*?)\]\s*as const/);
if (block === null) throw new Error('RENEWAL_REMINDER_WINDOWS was not found.');
const rows = [...block[1].matchAll(/\{\s*id:\s*'([^']+)'\s*,\s*daysFromExpiry:\s*(-?\d+)\s*}/g)]
  .map(([, id, days]) => `    ('${id}'::text, (${days})::smallint)`);
if (rows.length === 0) throw new Error('RENEWAL_REMINDER_WINDOWS has no rows.');
const generated = rows.join(',\n');
const marker = /( {4}-- GENERATED_RENEWAL_REMINDER_WINDOWS_START\r?\n)([\s\S]*?)( {4}-- GENERATED_RENEWAL_REMINDER_WINDOWS_END)/;
if (!marker.test(migration)) throw new Error('Generated renewal-window block markers were not found.');
const expected = migration.replace(marker, `$1${generated}\n$3`);
if (process.argv.includes('--write')) writeFileSync(migrationPath, expected);
else if (migration !== expected) throw new Error('RENEWAL_REMINDER_WINDOWS drift: run `pnpm run generate-renewal-reminder-windows`.');
