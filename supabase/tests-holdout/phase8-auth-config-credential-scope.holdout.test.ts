import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

const WORKFLOW_PATH = resolve(
  process.cwd(),
  '.github/workflows/auth-config.yml',
);

const GOOGLE_CREDENTIALS = [
  'GOOGLE_CLIENT_ID',
  'GOOGLE_CLIENT_SECRET',
] as const;
const SUPABASE_CREDENTIALS = [
  'SUPABASE_ACCESS_TOKEN',
  'SUPABASE_DB_PASSWORD',
] as const;

type Step = {
  readonly name: string;
  readonly source: string;
};

function workflowSource(): string {
  return readFileSync(WORKFLOW_PATH, 'utf8');
}

function stepsIn(source: string): readonly Step[] {
  const starts = [...source.matchAll(/^(\s*)- (?:name:\s*)?(.+)$/gm)];

  return starts.map((start, index) => {
    const indent = start[1]?.length ?? 0;
    const next = starts[index + 1];
    const end = next?.index ?? source.length;

    return {
      name: start[2] ?? '',
      source: source.slice(start.index, end),
    } satisfies Step;
  }).filter((step) => step.name.length > 0 && step.source.length > 0);
}

function secretAssignment(name: string): RegExp {
  return new RegExp(`\\b${name}\\s*:\\s*\\$\\{\\{\\s*secrets\\.[^}]+\\}\\}`, 'g');
}

function references(step: Step, name: string): boolean {
  return secretAssignment(name).test(step.source);
}

function occurrences(source: string, name: string): number {
  return [...source.matchAll(secretAssignment(name))].length;
}

describe('HARD-012 auth-configuration credential scope holdout', () => {
  it('uses manual dispatch and read-only repository permissions', () => {
    const source = workflowSource();

    expect(source).toMatch(/^on:\s*\n\s*workflow_dispatch:/m);
    expect(source).toMatch(/^permissions:\s*\n\s*contents:\s*read\s*$/m);
    expect(source).not.toMatch(/^\s*(?:actions|attestations|checks|deployments|id-token|issues|packages|pages|pull-requests|security-events|statuses):/m);
  });

  it('confines both Google credentials to one provider PATCH step', () => {
    const source = workflowSource();
    const steps = stepsIn(source);
    const credentialSteps = steps.filter((step) =>
      GOOGLE_CREDENTIALS.some((credential) => references(step, credential)),
    );

    expect(occurrences(source, GOOGLE_CREDENTIALS[0])).toBe(1);
    expect(occurrences(source, GOOGLE_CREDENTIALS[1])).toBe(1);
    expect(credentialSteps).toHaveLength(1);

    const [providerPatch] = credentialSteps;
    expect(providerPatch?.source).toMatch(/(?:curl|http).*\s(?:-X\s*)?PATCH\b/is);
    expect(providerPatch?.source).toMatch(/(?:external_google|google)/i);
  });

  it('keeps Supabase credentials step-local and only in operational steps', () => {
    const source = workflowSource();
    const steps = stepsIn(source);

    for (const credential of SUPABASE_CREDENTIALS) {
      const credentialSteps = steps.filter((step) => references(step, credential));

      expect(occurrences(source, credential)).toBe(credentialSteps.length);
      for (const step of credentialSteps) {
        expect(step.name).not.toMatch(/(?:checkout|setup)/i);
        expect(step.source).toMatch(/(?:supabase|curl|http|psql)/i);
      }
    }
  });

  it('does not expose any credential through workflow, job, checkout, or setup scope', () => {
    const source = workflowSource();
    const steps = stepsIn(source);
    const credentialPattern = /secrets\./;
    const allStepSource = steps.map((step) => step.source).join('');

    expect(source.replace(allStepSource, '')).not.toMatch(credentialPattern);
    for (const step of steps.filter((candidate) => /(?:checkout|setup)/i.test(candidate.name))) {
      expect(step.source).not.toMatch(credentialPattern);
    }
  });
});
