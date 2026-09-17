import { readFileSync, writeFileSync } from 'node:fs';

const renewalMigrationPath = 'supabase/migrations/20260915100007_phase6_comms.sql';
const platformMigrationPath = 'supabase/migrations/20260915100009_phase6_platform.sql';
const constants = readFileSync('packages/shared/src/config/constants.ts', 'utf8');
const renewalMigration = readFileSync(renewalMigrationPath, 'utf8');
const block = constants.match(/RENEWAL_REMINDER_WINDOWS\s*=\s*\[([\s\S]*?)\]\s*as const/);
if (block === null) throw new Error('RENEWAL_REMINDER_WINDOWS was not found.');
const rows = [...block[1].matchAll(/\{\s*id:\s*'([^']+)'\s*,\s*daysFromExpiry:\s*(-?\d+)\s*}/g)]
  .map(([, id, days]) => `    ('${id}'::text, (${days})::smallint)`);
if (rows.length === 0) throw new Error('RENEWAL_REMINDER_WINDOWS has no rows.');
const generated = rows.join(',\n');
const marker = /( {4}-- GENERATED_RENEWAL_REMINDER_WINDOWS_START\r?\n)([\s\S]*?)( {4}-- GENERATED_RENEWAL_REMINDER_WINDOWS_END)/;
if (!marker.test(renewalMigration)) throw new Error('Generated renewal-window block markers were not found.');
const renewalExpected = renewalMigration.replace(marker, `$1${generated}\n$3`);

const presetBlock = constants.match(/GYM_PRESET_SETTINGS\s*=\s*\{([\s\S]*?)\}\s*as const/);
if (presetBlock === null) throw new Error('GYM_PRESET_SETTINGS was not found.');
const presets = [...presetBlock[1].matchAll(/(\w+):\s*\{\s*noShowThresholdDays:\s*(\d+),\s*streakRule:\s*'([^']+)',\s*weeklyGoal:\s*(\d+),\s*maxFreezeDays:\s*(\d+),\s*pauseApproverRole:\s*'([^']+)'/g)];
if (presets.length === 0) throw new Error('GYM_PRESET_SETTINGS has no presets.');
const presetRows = presets.map(([, preset, threshold, streakRule, goal, freeze, approver]) =>
  `      '${preset}', jsonb_build_object('noShowThresholdDays', ${threshold}, 'streakRule', '${streakRule}', 'weeklyGoal', ${goal}, 'maxFreezeDays', ${freeze}, 'pauseApproverRole', '${approver}')`,
).join(',\n');
const platformMigration = readFileSync(platformMigrationPath, 'utf8');
const presetMarker = /( {4}-- GENERATED_GYM_PRESET_SETTINGS_START\r?\n)([\s\S]*?)( {4}-- GENERATED_GYM_PRESET_SETTINGS_END)/;
if (!presetMarker.test(platformMigration)) throw new Error('Generated gym-preset block markers were not found.');
const trialDays = constants.match(/TRIAL_DAYS\s*=\s*(\d+)/)?.[1];
const gymCodeLength = constants.match(/GYM_CODE_LENGTH\s*=\s*(\d+)/)?.[1];
if (trialDays === undefined || gymCodeLength === undefined) throw new Error('Onboarding scalar defaults were not found.');
const replaceScalar = (source, name, value) => {
  const scalarMarker = new RegExp(`( {4}-- GENERATED_${name}_START\\r?\\n)([\\s\\S]*?)( {4}-- GENERATED_${name}_END)`);
  if (!scalarMarker.test(source)) throw new Error(`Generated ${name} block markers were not found.`);
  return source.replace(scalarMarker, `$1${value}\n$3`);
};
const platformExpected = replaceScalar(
  replaceScalar(platformMigration.replace(presetMarker, `$1${presetRows}\n$3`), 'TRIAL_DAYS', trialDays),
  'GYM_CODE_LENGTH',
  gymCodeLength,
);
if (process.argv.includes('--write')) {
  writeFileSync(renewalMigrationPath, renewalExpected);
  writeFileSync(platformMigrationPath, platformExpected);
} else if (renewalMigration !== renewalExpected || platformMigration !== platformExpected) {
  throw new Error('Generated defaults drift: run `pnpm run generate-renewal-reminder-windows`.');
}
