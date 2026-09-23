import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const SOURCE = readFileSync(new URL('../../tests/load/phase8-morning-checkin.js', import.meta.url), 'utf8');
const REPOSITORY = fileURLToPath(new URL('../../', import.meta.url));
const PRIVATE_FILES = [
  'artifacts/phase8-load/private-fixture.json',
  'artifacts/phase8-load/baseline.json',
  'artifacts/phase8-load/cleanup.json',
];

describe('HARD-004 k6 fixture transport', () => {
  it('reads the large member and bearer-token fixture from a caller-selected local file', () => {
    expect(/\bopen\s*\(/.test(SOURCE)).toBe(true);
    expect(/__ENV\.[A-Z0-9_]*(?:FIXTURE|INPUT)[A-Z0-9_]*(?:PATH|FILE)|__ENV\.[A-Z0-9_]*(?:PATH|FILE)[A-Z0-9_]*(?:FIXTURE|INPUT)/i.test(SOURCE)).toBe(true);
    expect(/__ENV\.[A-Z0-9_]*(?:MEMBER_IDS|TOKENS|GYM_FIXTURES|TENANTS_JSON|FIXTURES_JSON)[A-Z0-9_]*/i.test(SOURCE)).toBe(false);
  });

  it('keeps the fixture and recovery manifests out of tracked source', () => {
    for (const path of PRIVATE_FILES) {
      const result = spawnSync('git', ['check-ignore', '--quiet', '--no-index', path], {
        cwd: REPOSITORY,
        encoding: 'utf8',
        windowsHide: true,
      });
      expect(result.status, `${path} must be gitignored`).toBe(0);
    }
  });
});
