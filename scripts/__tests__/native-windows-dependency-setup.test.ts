import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { platform, tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

type WindowsDependencyData = {
  run: Record<string, unknown>;
  nativeJobs: Record<string, unknown>[];
  guardianJobs: Record<string, unknown>[];
  artifactNames: string[];
  jobListingComplete: unknown;
  artifactListingComplete: unknown;
  teardownReview: Record<string, unknown>;
};
type WindowsDependencyVerifier = (input: unknown) => boolean;
type WindowsDependencyInstallCase = {
  installExit: number;
  metadataSetting: number;
  storePresent: boolean;
};

// Independently transcribed from the two frozen public contracts. No prior suite
// or classifier/workflow implementation was read to author these vectors.
const windowsDependencyNativeVector = [
  ['Set up job', 'success'],
  ['Set up runner', 'success'],
  ['Record adapter setup start before checkout', 'success'],
  ['Record hosted adapter setup start before checkout', 'skipped'],
  ['Run actions/checkout@v7', 'success'],
  ['Run pnpm/action-setup@v6', 'success'],
  ['Run actions/setup-node@v7', 'success'],
  ['Install the frozen adapter dependencies', 'failure'],
  ['Install the frozen hosted adapter dependencies', 'skipped'],
  ['Use the verified Git Bash executable for the pinned CLI installer', 'skipped'],
  ['Run supabase/setup-cli@v3', 'skipped'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Freeze full rollback-safe file and schema metadata', 'skipped'],
  ['Run actions/upload-artifact@v5', 'skipped'],
  ['Validate the full native suite with outside-worker recovery custody', 'skipped'],
  ['Retain sanitized native receipt', 'success'],
  ['Retain client-only smoke metadata', 'success'],
  ['Retain the explicit interim timing boundary', 'success'],
  ['Retain sanitized encrypted-artifact custody verification', 'success'],
  ['Post Run actions/setup-node@v7', 'skipped'],
  ['Post Run pnpm/action-setup@v6', 'success'],
  ['Post Run actions/checkout@v7', 'success'],
  ['Complete job', 'success'],
] as const;
const windowsDependencyOriginalVector = [
  ['Set up job', 'success'],
  ['Set up runner', 'failure'],
  ['Record adapter setup start before checkout', 'skipped'],
  ['Record hosted adapter setup start before checkout', 'skipped'],
  ['Run actions/checkout@v7', 'skipped'],
  ['Run pnpm/action-setup@v6', 'skipped'],
  ['Run actions/setup-node@v7', 'skipped'],
  ['Install the frozen adapter dependencies', 'skipped'],
  ['Install the frozen hosted adapter dependencies', 'skipped'],
  ['Use the verified Git Bash executable for the pinned CLI installer', 'skipped'],
  ['Run supabase/setup-cli@v3', 'skipped'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Freeze full rollback-safe file and schema metadata', 'skipped'],
  ['Run actions/upload-artifact@v5', 'skipped'],
  ['Validate the full native suite with outside-worker recovery custody', 'skipped'],
  ['Retain sanitized native receipt', 'success'],
  ['Retain client-only smoke metadata', 'success'],
  ['Retain the explicit interim timing boundary', 'success'],
  ['Retain sanitized encrypted-artifact custody verification', 'success'],
  ['Complete job', 'success'],
] as const;
const windowsDependencyGuardianVector = [
  ['Set up job', 'success'],
  ['Run actions/checkout@v7', 'success'],
  ['Run pnpm/action-setup@v6', 'success'],
  ['Run actions/setup-node@v7', 'success'],
  ['Run pnpm install --frozen-lockfile --filter "@gymloop/shared..." --prod --ignore-scripts', 'success'],
  ['Run supabase/setup-cli@v3', 'success'],
  ['Find the exact armed receipt, including an earlier attempt of this run', 'failure'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Run supabase link --project-ref "$PROJECT_REF" --yes', 'skipped'],
  ['Restore and freshly verify only the captured role-global timeout', 'skipped'],
  ['Retain independently hosted restoration evidence', 'skipped'],
  ['Post Run supabase/setup-cli@v3', 'success'],
  ['Post Run actions/setup-node@v7', 'skipped'],
  ['Post Run pnpm/action-setup@v6', 'success'],
  ['Post Run actions/checkout@v7', 'success'],
  ['Complete job', 'success'],
] as const;

function windowsDependencyFixture(original = false): WindowsDependencyData {
  const run = {
    id: '37850045697', attempt: '1',
    sourceSha: 'aa671256fec55299f5aeb28cae4f17468f16a4f7',
    repositoryId: 1001, repository: 'OGUN01/gymloop',
    headRepositoryId: 1001, headRepository: 'OGUN01/gymloop',
    event: 'push', path: '.github/workflows/db.yml', branch: 'main',
    status: 'completed', conclusion: 'failure',
  };
  const native = {
    id: 113561160570, runId: run.id, attempt: run.attempt,
    sourceSha: run.sourceSha, name: 'pgtap', status: 'completed',
    conclusion: 'failure', runnerId: 38, runnerName: 'independent-visible-native',
    runnerGroupName: 'Default',
    labels: ['self-hosted', 'Windows', 'X64',
      `${NATIVE_DB_VALIDATION.labelPrefix}-${run.id}-1-${run.sourceSha.slice(0, NATIVE_DB_VALIDATION.labelShaLength)}`],
    steps: (original ? windowsDependencyOriginalVector : windowsDependencyNativeVector)
      .map(([name, conclusion]) => ({ name, status: 'completed', conclusion })),
  };
  const guardian = {
    id: 113561160571, runId: run.id, attempt: run.attempt,
    sourceSha: run.sourceSha, name: 'timeout-guardian', status: 'completed',
    conclusion: 'failure', runnerId: 72, runnerName: 'GitHub Actions 72',
    runnerGroupName: 'GitHub Actions', labels: ['ubuntu-latest'],
    steps: windowsDependencyGuardianVector
      .map(([name, conclusion]) => ({ name, status: 'completed', conclusion })),
  };
  return {
    run, nativeJobs: [native], guardianJobs: [guardian],
    artifactNames: [`native-db-schema-${run.id}-1`, `native-db-ci-job-${run.id}-1`],
    jobListingComplete: true, artifactListingComplete: true,
    teardownReview: {
      formatVersion: NATIVE_DB_VALIDATION.formatVersion,
      runId: `${run.id}-1`, sourceSha: run.sourceSha, jobId: native.id.toString(),
      runnerId: native.runnerId, runnerEnvironment: 'self-hosted',
      privateProofSha256: 'c'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
      nativeProcessesStopped: true, ownedContainersStopped: true,
      runnerDeregistered: true, verifiedAt: '2026-10-09T06:00:00.000Z',
    },
  };
}
function windowsDependencyAlter(change: (input: WindowsDependencyData) => void): WindowsDependencyData {
  const input = windowsDependencyFixture();
  change(input);
  return input;
}
let windowsDependencyClassify: WindowsDependencyVerifier;
beforeAll(async () => {
  // Opaque public interface invocation; implementation bytes are never rendered.
  const imported = await import('../pgtap/unarmed-setup-failure.mjs');
  windowsDependencyClassify = imported.verifyUnarmedNativeSetupFailure as WindowsDependencyVerifier;
});

describe('independent exact Windows dependency setup failure contract', () => {
  it('accepts the complete dependency failure and physical closure', () => {
    expect(windowsDependencyClassify(windowsDependencyFixture())).toBe(true);
  });
  it('accepts the same exact vector on workflow_dispatch', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.run.event = 'workflow_dispatch'; }))).toBe(true);
  });
  it('accepts order-independent unique native labels and complete artifact pair', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => {
      (input.nativeJobs[0].labels as string[]).reverse();
      input.artifactNames.reverse();
    }))).toBe(true);
  });
  it('preserves exact original pre-checkout setup acceptance', () => {
    expect(windowsDependencyClassify(windowsDependencyFixture(true))).toBe(true);
  });
  it('preserves original setup acceptance on dispatch with reordered labels', () => {
    const input = windowsDependencyFixture(true);
    input.run.event = 'workflow_dispatch';
    (input.nativeJobs[0].labels as string[]).reverse();
    expect(windowsDependencyClassify(input)).toBe(true);
  });

  it.each([undefined, null, false, '', [], new Date(), Object.create({ inherited: true })])('refuses non-record input %#', value => {
    expect(windowsDependencyClassify(value)).toBe(false);
  });
  it('refuses reflected input exceptions', () => {
    const value = new Proxy({}, { ownKeys: () => { throw new Error('independent reflection sentinel'); } });
    expect(windowsDependencyClassify(value)).toBe(false);
  });
  for (const key of Object.keys(windowsDependencyFixture())) {
    it(`refuses missing top-level ${key}`, () => {
      const value = windowsDependencyFixture() as unknown as Record<string, unknown>;
      delete value[key];
      expect(windowsDependencyClassify(value)).toBe(false);
    });
    it(`refuses accessor top-level ${key} without observing it`, () => {
      const value = windowsDependencyFixture();
      let observed = false;
      Object.defineProperty(value, key, { enumerable: true, get: () => { observed = true; throw new Error('independent getter sentinel'); } });
      expect(windowsDependencyClassify(value)).toBe(false);
      expect(observed).toBe(false);
    });
  }
  it('refuses an extra top-level property', () => {
    expect(windowsDependencyClassify({ ...windowsDependencyFixture(), extra: true })).toBe(false);
  });
  it('refuses a top-level symbol', () => {
    expect(windowsDependencyClassify({ ...windowsDependencyFixture(), [Symbol('extra')]: true })).toBe(false);
  });
  it('refuses inherited top-level data', () => {
    expect(windowsDependencyClassify(Object.create(windowsDependencyFixture()))).toBe(false);
  });
  for (const key of ['jobListingComplete', 'artifactListingComplete'] as const) {
    it.each([false, 'true', 1, undefined, null, []])(`requires literal true for ${key}: %#`, value => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { input[key] = value; }))).toBe(false);
    });
  }

  for (const field of Object.keys(windowsDependencyFixture().run)) {
    it(`refuses missing run ${field}`, () => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { delete input.run[field]; }))).toBe(false);
    });
    it(`refuses accessor run ${field} without observing it`, () => {
      let observed = false;
      const value = windowsDependencyAlter(input => {
        Object.defineProperty(input.run, field, { enumerable: true, get: () => { observed = true; return undefined; } });
      });
      expect(windowsDependencyClassify(value)).toBe(false);
      expect(observed).toBe(false);
    });
  }
  it.each([
    ['id', '0'], ['id', '01'], ['id', '-1'], ['id', '1.2'], ['id', '9007199254740992'], ['id', 1],
    ['attempt', '2'], ['attempt', 1], ['sourceSha', 'A'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    ['sourceSha', 'g'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)], ['sourceSha', 'a'],
    ['repositoryId', 0], ['repositoryId', '1001'], ['repositoryId', Number.MAX_SAFE_INTEGER + 1],
    ['headRepositoryId', 0], ['headRepositoryId', '1001'], ['headRepositoryId', 1002],
    ['repository', 'other/gymloop'], ['headRepository', 'OGUN01/other'],
    ['event', 'pull_request'], ['event', 'schedule'], ['path', '.github/workflows/ci.yml'],
    ['branch', 'other'], ['status', 'in_progress'], ['conclusion', 'cancelled'], ['conclusion', 'success'],
  ])('refuses run mismatch %s %#', (field, value) => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.run[field as string] = value; }))).toBe(false);
  });
  it('refuses an extra run field', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.run.extra = true; }))).toBe(false);
  });
  it('refuses a run custom prototype', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { Object.setPrototypeOf(input.run, { extra: true }); }))).toBe(false);
  });

  for (const list of ['nativeJobs', 'guardianJobs'] as const) {
    it(`refuses empty ${list}`, () => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { input[list] = []; }))).toBe(false);
    });
    it(`refuses duplicated ${list}`, () => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { input[list].push(structuredClone(input[list][0])); }))).toBe(false);
    });
    it(`refuses sparse ${list}`, () => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { delete input[list][0]; }))).toBe(false);
    });
    it(`refuses extra array data on ${list}`, () => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { Object.defineProperty(input[list], 'extra', { value: true }); }))).toBe(false);
    });
    it(`refuses accessor array item on ${list} without observing it`, () => {
      let observed = false;
      const value = windowsDependencyAlter(input => {
        Object.defineProperty(input[list], '0', { enumerable: true, get: () => { observed = true; return {}; } });
      });
      expect(windowsDependencyClassify(value)).toBe(false);
      expect(observed).toBe(false);
    });
    for (const field of Object.keys(windowsDependencyFixture()[list][0])) {
      it(`refuses missing ${list} ${field}`, () => {
        expect(windowsDependencyClassify(windowsDependencyAlter(input => { delete input[list][0][field]; }))).toBe(false);
      });
      it(`refuses accessor ${list} ${field}`, () => {
        let observed = false;
        const value = windowsDependencyAlter(input => {
          Object.defineProperty(input[list][0], field, { enumerable: true, get: () => { observed = true; return undefined; } });
        });
        expect(windowsDependencyClassify(value)).toBe(false);
        expect(observed).toBe(false);
      });
    }
    it.each([
      ['id', 0], ['id', -1], ['id', '1'], ['id', Number.MIN_VALUE], ['id', Number.MAX_SAFE_INTEGER + 1],
      ['runId', '1'], ['runId', 37850045697], ['attempt', '2'], ['attempt', 1],
      ['sourceSha', 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
      ['status', 'in_progress'], ['conclusion', 'success'], ['runnerId', 0], ['runnerId', '1'],
      ['runnerId', Number.MIN_VALUE], ['runnerId', Number.MAX_SAFE_INTEGER + 1],
      ['runnerName', ''], ['runnerName', null],
    ])(`refuses ${list} identity %s %#`, (field, value) => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { input[list][0][field as string] = value; }))).toBe(false);
    });
    it(`refuses extra ${list} job key`, () => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { input[list][0].extra = true; }))).toBe(false);
    });
    it(`refuses custom ${list} job prototype`, () => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { Object.setPrototypeOf(input[list][0], { extra: true }); }))).toBe(false);
    });
  }
  it('refuses native and guardian duplicate job identity', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.guardianJobs[0].id = input.nativeJobs[0].id; }))).toBe(false);
  });
  it('refuses native and guardian duplicate runner identity', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => {
      input.guardianJobs[0].runnerId = input.nativeJobs[0].runnerId;
      input.guardianJobs[0].runnerName = `GitHub Actions ${input.nativeJobs[0].runnerId}`;
    }))).toBe(false);
  });
  it.each([
    ['nativeJobs', 'name', 'timeout-guardian'], ['nativeJobs', 'runnerGroupName', 'GitHub Actions'],
    ['guardianJobs', 'name', 'pgtap'], ['guardianJobs', 'runnerGroupName', 'Default'],
    ['guardianJobs', 'runnerName', 'GitHub Actions 73'],
  ] as const)('refuses role metadata %s %s', (list, field, value) => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input[list][0][field] = value; }))).toBe(false);
  });
  for (const index of windowsDependencyFixture().nativeJobs[0].labels as string[]) {
    it(`refuses a missing native label ${index}`, () => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => {
        input.nativeJobs[0].labels = (input.nativeJobs[0].labels as string[]).filter(label => label !== index);
      }))).toBe(false);
    });
  }
  it.each(['self-hosted', 'windows', 'x64', 'ubuntu-latest', 'unknown'])('refuses changed native label %s', value => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => {
      (input.nativeJobs[0].labels as string[])[1] = value;
    }))).toBe(false);
  });
  it('refuses a valid-looking source-unbound native label', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => {
      (input.nativeJobs[0].labels as string[])[3] = `${NATIVE_DB_VALIDATION.labelPrefix}-${input.run.id}-1-${'b'.repeat(NATIVE_DB_VALIDATION.labelShaLength)}`;
    }))).toBe(false);
  });
  it('refuses duplicate native labels', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => {
      (input.nativeJobs[0].labels as string[])[1] = (input.nativeJobs[0].labels as string[])[0];
    }))).toBe(false);
  });
  it('refuses a second guardian label', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.guardianJobs[0].labels = ['ubuntu-latest', 'self-hosted']; }))).toBe(false);
  });
  it('refuses a non-hosted guardian label', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.guardianJobs[0].labels = ['Windows']; }))).toBe(false);
  });
  for (const list of ['nativeJobs', 'guardianJobs'] as const) {
    it(`refuses sparse ${list} labels`, () => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { delete (input[list][0].labels as string[])[0]; }))).toBe(false);
    });
    it(`refuses an accessor in ${list} labels`, () => {
      let observed = false;
      const value = windowsDependencyAlter(input => {
        Object.defineProperty(input[list][0].labels, '0', { get: () => { observed = true; return 'Windows'; } });
      });
      expect(windowsDependencyClassify(value)).toBe(false);
      expect(observed).toBe(false);
    });
  }

  for (const field of Object.keys(windowsDependencyFixture().teardownReview)) {
    it(`requires physical receipt ${field}`, () => {
      expect(windowsDependencyClassify(windowsDependencyAlter(input => { delete input.teardownReview[field]; }))).toBe(false);
    });
    it(`refuses physical receipt accessor ${field}`, () => {
      let observed = false;
      const value = windowsDependencyAlter(input => {
        Object.defineProperty(input.teardownReview, field, { enumerable: true, get: () => { observed = true; return undefined; } });
      });
      expect(windowsDependencyClassify(value)).toBe(false);
      expect(observed).toBe(false);
    });
  }
  it.each([
    ['formatVersion', '1'], ['runId', '37850045697-2'], ['sourceSha', 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    ['jobId', '113561160571'], ['jobId', 113561160570], ['runnerId', 0], ['runnerId', 39],
    ['runnerEnvironment', 'github-hosted'], ['privateProofSha256', ''],
    ['privateProofSha256', 'C'.repeat(NATIVE_DB_VALIDATION.digestHexLength)],
    ['nativeProcessesStopped', false], ['ownedContainersStopped', false], ['runnerDeregistered', false],
    ['nativeProcessesStopped', 'true'], ['ownedContainersStopped', 1], ['runnerDeregistered', null],
    ['verifiedAt', 'not-a-time'], ['verifiedAt', '2026-02-30T06:00:00.000Z'],
  ])('refuses unverified physical receipt %s %#', (field, value) => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.teardownReview[field as string] = value; }))).toBe(false);
  });
  it('refuses a wrapped physical receipt', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.teardownReview = { receipt: input.teardownReview }; }))).toBe(false);
  });
  it('refuses an extra physical receipt field', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.teardownReview.extra = true; }))).toBe(false);
  });
  it('refuses inherited physical receipt metadata', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.teardownReview = Object.create(input.teardownReview); }))).toBe(false);
  });

  it('refuses an empty artifact listing', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.artifactNames = []; }))).toBe(false);
  });
  it('refuses duplicated artifact pair', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.artifactNames.push(input.artifactNames[0]); }))).toBe(false);
  });
  it('refuses a missing artifact from the complete pair', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.artifactNames.pop(); }))).toBe(false);
  });
  it('refuses sparse artifact listing', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { delete input.artifactNames[0]; }))).toBe(false);
  });
  it('refuses an artifact listing accessor', () => {
    let observed = false;
    const value = windowsDependencyAlter(input => {
      Object.defineProperty(input.artifactNames, '0', { get: () => { observed = true; return 'unexpected'; } });
    });
    expect(windowsDependencyClassify(value)).toBe(false);
    expect(observed).toBe(false);
  });
  it.each(['recovery', 'receipt', 'smoke', 'manifest', 'timing', 'private-custody', 'restoration', 'unknown'])('refuses additional %s artifact', kind => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.artifactNames.push(`native-db-${kind}-${input.run.id}-1`); }))).toBe(false);
  });
  it('refuses source-attempt-unbound artifact pair', () => {
    expect(windowsDependencyClassify(windowsDependencyAlter(input => { input.artifactNames = ['native-db-schema-37850045697-2', 'native-db-ci-job-37850045697-2']; }))).toBe(false);
  });

  for (const [role, vector, original] of [
    ['nativeJobs', windowsDependencyNativeVector, false],
    ['nativeJobs', windowsDependencyOriginalVector, true],
    ['guardianJobs', windowsDependencyGuardianVector, false],
  ] as const) {
    for (const [index] of vector.entries()) {
      for (const field of ['name', 'status', 'conclusion'] as const) {
        it(`refuses ${original ? 'original' : 'dependency'} ${role} step ${index} altered ${field}`, () => {
          const input = windowsDependencyFixture(original);
          const steps = input[role][0].steps as Record<string, unknown>[];
          steps[index][field] = field === 'name' ? `${steps[index].name} extra` : field === 'status' ? 'in_progress' : steps[index].conclusion === 'success' ? 'skipped' : 'success';
          expect(windowsDependencyClassify(input)).toBe(false);
        });
        it(`refuses ${original ? 'original' : 'dependency'} ${role} step ${index} missing ${field}`, () => {
          const input = windowsDependencyFixture(original);
          delete (input[role][0].steps as Record<string, unknown>[])[index][field];
          expect(windowsDependencyClassify(input)).toBe(false);
        });
      }
      it(`refuses ${original ? 'original' : 'dependency'} ${role} step ${index} hole`, () => {
        const input = windowsDependencyFixture(original);
        delete (input[role][0].steps as Record<string, unknown>[])[index];
        expect(windowsDependencyClassify(input)).toBe(false);
      });
      it(`refuses ${original ? 'original' : 'dependency'} ${role} step ${index} duplicate`, () => {
        const input = windowsDependencyFixture(original);
        const steps = input[role][0].steps as Record<string, unknown>[];
        steps.splice(index, 0, structuredClone(steps[index]));
        expect(windowsDependencyClassify(input)).toBe(false);
      });
      it(`refuses ${original ? 'original' : 'dependency'} ${role} step ${index} accessor`, () => {
        const input = windowsDependencyFixture(original);
        let observed = false;
        Object.defineProperty((input[role][0].steps as Record<string, unknown>[])[index], 'name', { get: () => { observed = true; return undefined; } });
        expect(windowsDependencyClassify(input)).toBe(false);
        expect(observed).toBe(false);
      });
      it(`refuses ${original ? 'original' : 'dependency'} ${role} step ${index} extra key`, () => {
        const input = windowsDependencyFixture(original);
        (input[role][0].steps as Record<string, unknown>[])[index].extra = true;
        expect(windowsDependencyClassify(input)).toBe(false);
      });
    }
    it(`refuses reordered ${original ? 'original' : 'dependency'} ${role} vector`, () => {
      const input = windowsDependencyFixture(original);
      (input[role][0].steps as Record<string, unknown>[]).reverse();
      expect(windowsDependencyClassify(input)).toBe(false);
    });
    it(`refuses shortened ${original ? 'original' : 'dependency'} ${role} vector`, () => {
      const input = windowsDependencyFixture(original);
      (input[role][0].steps as Record<string, unknown>[]).pop();
      expect(windowsDependencyClassify(input)).toBe(false);
    });
  }
});

// Transport clarified and frozen before these assertions. The author's actual
// pnpm installation separately proves setting 24 and discloses its native hash
// floor; this port checks the opaque workflow's refusal behavior only.
function windowsDependencyWorkflowStep(name: string): string {
  const lines = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8').split(/\r?\n/);
  const at = lines.findIndex(line => /^\s*- name:/.test(line) && line.includes(name));
  expect(at).toBeGreaterThanOrEqual(0);
  const prefix = lines[at].match(/^\s*/)?.[0] ?? '';
  const next = lines.findIndex((line, index) => index > at && line.startsWith(`${prefix}- `));
  return lines.slice(at, next < 0 ? lines.length : next).join('\n');
}
function windowsDependencyInstallProbe(input: WindowsDependencyInstallCase) {
  const root = mkdtempSync(join(tmpdir(), 'gymloop-visible-windows-install-'));
  const response = { exitCode: null as number | null, actualSetting: '', arguments: [] as string[], cleanedUp: false };
  try {
    const quoted = root.replace(/'/g, "''");
    const protection = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', `
$ErrorActionPreference='Stop'
$fixture='${quoted}'
$security=[Security.AccessControl.DirectorySecurity]::new()
$security.SetAccessRuleProtection($true,$false)
foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')){
 $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
}
[IO.Directory]::SetAccessControl($fixture,$security)
`], { encoding: 'utf8', timeout: NATIVE_DB_VALIDATION.processStopGraceMs, windowsHide: true });
    if (protection.status !== 0) throw new Error('VISIBLE_INSTALL_FIXTURE_PROTECTION_REFUSED');
    const constantsDirectory = join(root, 'packages', 'shared', 'src', 'config');
    mkdirSync(constantsDirectory, { recursive: true });
    copyFileSync(new URL('../../packages/shared/src/config/constants.ts', import.meta.url), join(constantsDirectory, 'constants.ts'));
    const step = windowsDependencyWorkflowStep('Install the frozen adapter dependencies');
    const source = step.match(/^\s*run:\s*\|\s*\n([\s\S]*)/m)?.[1];
    if (!source) throw new Error('VISIBLE_INSTALL_STEP_LITERAL_BLOCK_REQUIRED');
    const nonempty = source.split('\n').filter(line => line.trim());
    const indent = Math.min(...nonempty.map(line => line.match(/^\s*/)?.[0].length ?? 0));
    const body = source.split('\n').map(line => line.slice(indent)).join('\n');
    const metadata = JSON.stringify({ virtualStoreDirMaxLength: input.metadataSetting });
    const script = join(root, 'visible-install-driver.ps1');
    writeFileSync(script, `$ErrorActionPreference='Stop'
function global:pnpm {
 param([Parameter(ValueFromRemainingArguments=$true)][string[]]$FixtureArguments)
 $null=[IO.Directory]::CreateDirectory('node_modules')
 [IO.File]::WriteAllText('node_modules/.modules.yaml','${metadata}')
 ${input.storePresent ? "$null=[IO.Directory]::CreateDirectory('.p')" : ''}
 $record=[ordered]@{actualSetting=[Environment]::GetEnvironmentVariable('PNPM_CONFIG_VIRTUAL_STORE_DIR_MAX_LENGTH','Process');arguments=@($FixtureArguments)}
 [IO.File]::WriteAllText('visible-install-port.json',($record|ConvertTo-Json -Depth 4))
 $global:LASTEXITCODE=${input.installExit}
}
${body}
`, 'utf8');
    const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-File', script], {
      cwd: root, encoding: 'utf8', timeout: NATIVE_DB_VALIDATION.processStopGraceMs, windowsHide: true,
    });
    response.exitCode = result.status;
    const portPath = join(root, 'visible-install-port.json');
    if (existsSync(portPath)) {
      const port = JSON.parse(readFileSync(portPath, 'utf8')) as { actualSetting: string; arguments: string[] };
      response.actualSetting = port.actualSetting;
      response.arguments = port.arguments;
    }
    return response;
  } finally {
    if (resolve(root).startsWith(`${resolve(tmpdir())}${sep}`)) {
      rmSync(root, { recursive: true, force: true });
      response.cleanedUp = !existsSync(root);
    }
  }
}
describe('independent frozen dependency installation guards', () => {
  it('preserves the production-only shared filter, frozen lock and ignored scripts', () => {
    const step = windowsDependencyWorkflowStep('Install the frozen adapter dependencies');
    expect(step).toContain('--frozen-lockfile --filter "@gymloop/shared..." --prod --ignore-scripts');
    expect(step).toContain('NATIVE_DB_VALIDATION.virtualStoreDirMaxLength');
  });
  it('pins the independently exercised package manager', () => {
    const manifest = JSON.parse(readFileSync(new URL('../../package.json', import.meta.url), 'utf8')) as { packageManager: string };
    expect(manifest.packageManager).toBe('pnpm@12.3.4');
    expect({ compactionSetting: NATIVE_DB_VALIDATION.virtualStoreDirMaxLength }).toEqual({ compactionSetting: 24 });
  });
  it('uses only the effective step-local transport and supported short-store value form', () => {
    const step = windowsDependencyWorkflowStep('Install the frozen adapter dependencies');
    expect(step).toMatch(/\$env:PNPM_CONFIG_VIRTUAL_STORE_DIR_MAX_LENGTH\s*=\s*(?:\[string\])?\s*"?\$storeLimit"?/);
    expect(step).toContain('pnpm install --frozen-lockfile --filter "@gymloop/shared..." --prod --ignore-scripts --virtual-store-dir=.p');
    expect(step).not.toMatch(/--virtual-store-dir\s+\.p|--virtual-store-dir-max-length|--config\.virtual/);
  });
  it('requires actual installation metadata and the short store before native work', () => {
    const step = windowsDependencyWorkflowStep('Install the frozen adapter dependencies');
    expect(step).toMatch(/node_modules[\\/]\.modules\.yaml/);
    expect(step).toContain('virtualStoreDirMaxLength');
    expect(step).toMatch(/\.p/);
  });
  it('keeps separate Windows and hosted selection guards', () => {
    expect(windowsDependencyWorkflowStep('Install the frozen adapter dependencies')).toMatch(/if:\s*(?:\$\{\{\s*)?runner\.os\s*==\s*['"]Windows['"]/);
    expect(windowsDependencyWorkflowStep('Install the frozen hosted adapter dependencies')).toMatch(/if:\s*(?:\$\{\{\s*)?runner\.os\s*!=\s*['"]Windows['"]/);
  });
  it('preserves the hosted installation command', () => {
    const step = windowsDependencyWorkflowStep('Install the frozen hosted adapter dependencies');
    expect(step.match(/pnpm install[^\n]+/)?.[0].trim()).toBe('pnpm install --frozen-lockfile --filter "@gymloop/shared..." --prod --ignore-scripts');
  });
  it.skipIf(platform() !== 'win32')('executes the opaque Windows step against successful exact metadata only', () => {
    const result = windowsDependencyInstallProbe({ installExit: 0, metadataSetting: NATIVE_DB_VALIDATION.virtualStoreDirMaxLength, storePresent: true });
    expect(result.exitCode).toBe(0);
    expect(result.actualSetting).toBe(String(NATIVE_DB_VALIDATION.virtualStoreDirMaxLength));
    expect(result.arguments).toEqual(['install', '--frozen-lockfile', '--filter', '@gymloop/shared...', '--prod', '--ignore-scripts', '--virtual-store-dir=.p']);
    expect(result.cleanedUp).toBe(true);
  }, NATIVE_DB_VALIDATION.processStopGraceMs);
  for (const [name, scenario] of [
    ['failed installation', { installExit: 1, metadataSetting: NATIVE_DB_VALIDATION.virtualStoreDirMaxLength, storePresent: true }],
    ['ignored/default setting', { installExit: 0, metadataSetting: 60, storePresent: true }],
    ['missing short store', { installExit: 0, metadataSetting: NATIVE_DB_VALIDATION.virtualStoreDirMaxLength, storePresent: false }],
  ] as const) {
    it.skipIf(platform() !== 'win32')(`refuses ${name} through the opaque Windows step`, () => {
      const result = windowsDependencyInstallProbe(scenario);
      expect(result.exitCode).not.toBeNull();
      expect(result.exitCode).not.toBe(0);
      expect(result.cleanedUp).toBe(true);
    }, NATIVE_DB_VALIDATION.processStopGraceMs);
  }
});
