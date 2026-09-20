import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const WORKFLOW = readFileSync(
  new URL('../../.github/workflows/auth-config.yml', import.meta.url),
  'utf8',
);

const topLevelEnv = /^env:\s*$(.*?)(?=^jobs:)/ms.exec(WORKFLOW)?.[1] ?? '';
const patchStep = /- name:\s*Patch the reviewed auth settings[\s\S]*$/m.exec(WORKFLOW)?.[0] ?? '';
const setupActionSteps = [
  ...WORKFLOW.matchAll(
    /^[ \t]*- uses:\s*(?:actions\/checkout|supabase\/setup-cli)[^\r\n]*(?:\r?\n(?![ \t]*- (?:name|uses|run):)[^\r\n]*)*/gm,
  ),
].map(([source]) => source);

describe('manual auth-configuration workflow credential boundaries', () => {
  it('declares only read-only repository access', () => {
    expect(WORKFLOW).toMatch(/^permissions:\s*\n\s+contents:\s*read\s*$/m);
    expect(WORKFLOW).not.toMatch(/^\s+[A-Za-z-]+:\s*(write|read-write)\s*$/m);
  });

  it('keeps Google OAuth credentials together in exactly one patch step', () => {
    expect(topLevelEnv).not.toMatch(/secrets\.[A-Z0-9_]*(GOOGLE|OAUTH)/i);
    expect(patchStep).toMatch(/secrets\.[A-Z0-9_]*GOOGLE[A-Z0-9_]*(CLIENT_ID|ID)/i);
    expect(patchStep).toMatch(/secrets\.[A-Z0-9_]*GOOGLE[A-Z0-9_]*(CLIENT_SECRET|SECRET)/i);
  });

  it('does not expose Supabase credentials outside the steps that use them', () => {
    expect(topLevelEnv).not.toMatch(/secrets\.[A-Z0-9_]*(SUPABASE|DB_PASSWORD)/i);
    expect(patchStep).toMatch(/secrets\.[A-Z0-9_]*(SUPABASE|ACCESS_TOKEN)/i);
    expect(patchStep).not.toMatch(/secrets\.[A-Z0-9_]*(DB_PASSWORD|PASSWORD)/i);
    expect(WORKFLOW).toMatch(/secrets\.[A-Z0-9_]*(DB_PASSWORD|PASSWORD)/i);
    expect(WORKFLOW).toMatch(/supabase\s+(link|db\s+query)/i);
  });

  it('gives checkout and setup actions no live secrets', () => {
    expect(setupActionSteps.length).toBeGreaterThan(0);
    for (const source of setupActionSteps) {
      expect(source).not.toMatch(/secrets\.[A-Z0-9_]+/);
    }
  });
});
