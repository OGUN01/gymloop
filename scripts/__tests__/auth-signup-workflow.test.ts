import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// ADR-173: public Auth signup is closed before closed-test testers are
// provisioned. This workflow is the only mechanism, so its boundaries are pinned.
const WORKFLOW = readFileSync(
  new URL('../../.github/workflows/auth-signup.yml', import.meta.url),
  'utf8',
);

const topLevelEnv = /^env:\s*$(.*?)(?=^jobs:)/ms.exec(WORKFLOW)?.[1] ?? '';
const steps = WORKFLOW.split(/^\s+- name:/m).slice(1);
const stepsUsingSecrets = steps.filter((step) => /secrets\./.test(step));
const patchBodies = [...WORKFLOW.matchAll(/-X PATCH[\s\S]*?-d\s+'([^']*)'/g)].map((match) => match[1]);

describe('manual Auth signup workflow (ADR-173)', () => {
  it('runs only when dispatched by hand, with read-only repository access', () => {
    expect(WORKFLOW).toMatch(/^on:\s*\n\s+workflow_dispatch:/m);
    expect(WORKFLOW).not.toMatch(/^\s+(push|pull_request|schedule):/m);
    expect(WORKFLOW).toMatch(/^permissions:\s*\n\s+contents:\s*read\s*$/m);
  });

  it('offers exactly report, disable-signup and enable-signup, defaulting to report', () => {
    expect(WORKFLOW).toMatch(/type:\s*choice/);
    expect(WORKFLOW).toMatch(/default:\s*report/);
    for (const mode of ['report', 'disable-signup', 'enable-signup']) expect(WORKFLOW).toContain(`- ${mode}`);
  });

  it('keeps the access token out of the top-level env and inside the one API step', () => {
    expect(topLevelEnv).not.toMatch(/secrets\./);
    expect(stepsUsingSecrets).toHaveLength(1);
    expect(stepsUsingSecrets[0]).toMatch(/secrets\.SUPABASE_ACCESS_TOKEN/);
    expect(WORKFLOW).not.toMatch(/secrets\.(SUPABASE_DB_PASSWORD|SUPABASE_SERVICE_ROLE_KEY|DEMO_ACCOUNT_PASSWORD)/);
  });

  it('patches only disable_signup, and only outside report mode', () => {
    expect(patchBodies.length).toBeGreaterThan(0);
    for (const body of patchBodies) expect(body.replace(/\s/g, '')).toMatch(/^\{"disable_signup":(true|false)\}$/);
    expect(WORKFLOW).toMatch(/if \[ "\$MODE" = "report" \]/);
  });

  it('prints an allow-list of non-secret fields, never the raw config', () => {
    expect(WORKFLOW).toMatch(/disable_signup/);
    expect(WORKFLOW).toMatch(/mailer_autoconfirm/);
    expect(WORKFLOW).toMatch(/rate_limit_/);
    expect(WORKFLOW).not.toMatch(/cat \/tmp\/auth[^\n]*\.json/);
    expect(WORKFLOW).not.toMatch(/'(external_google_secret|smtp_pass|security_captcha_secret)'/);
  });
});
