import { afterEach, describe, expect, it, vi } from 'vitest';

import { pilotAcceptanceEnv } from '../env';

const ACCEPTANCE_LITERAL = 'ONE_SHARED_PRELAUNCH_PROJECT';

describe('pilotAcceptanceEnv holdout', () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('accepts only the exact manual pilot opt-in literal', () => {
    vi.stubEnv('PILOT_SHARED_PROJECT_ACCEPTANCE', ACCEPTANCE_LITERAL);

    expect(pilotAcceptanceEnv()).toEqual({
      PILOT_SHARED_PROJECT_ACCEPTANCE: ACCEPTANCE_LITERAL,
    });
  });

  it.each([
    ['missing', undefined],
    ['true', 'true'],
    ['truthy number', '1'],
    ['affirmative word', 'yes'],
    ['case variant', 'one_shared_prelaunch_project'],
    ['trailing whitespace', `${ACCEPTANCE_LITERAL} `],
  ])('fails closed for %s rather than enabling a run', (_label, value) => {
    vi.stubEnv('PILOT_SHARED_PROJECT_ACCEPTANCE', value);

    expect(() => pilotAcceptanceEnv()).toThrow();
  });
});
