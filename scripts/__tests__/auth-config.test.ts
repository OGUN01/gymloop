import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Two Phase 2 requirements are not reachable from pgTAP — they are properties of
// a config file, not of the database — and a blind holdout author pointed out
// that they were therefore guarded by nothing at all. This file is that guard.
//
// It deliberately reads the .toml as text rather than parsing it: the assertions
// are about three specific lines, the repo has no TOML parser as a dependency,
// and adding one to check three lines is exactly the kind of trade AGENTS.md's
// reuse rule exists to refuse.

const CONFIG = readFileSync(new URL('../../supabase/config.toml', import.meta.url), 'utf8');

// The Supabase default. An access token lives this long after the refresh token
// behind it has been deleted, so it is the ceiling on how long a revoked
// privilege keeps working (openspec/specs/identity, "The access token's lifetime
// is chosen, not defaulted").
const SUPABASE_DEFAULT_JWT_EXPIRY_SECONDS = 3600;

describe('supabase/config.toml records the Phase 2 auth decisions', () => {
  it('sets an access-token lifetime shorter than the platform default', () => {
    const match = /^jwt_expiry\s*=\s*(\d+)\s*$/m.exec(CONFIG);
    expect(match, 'jwt_expiry is not set at all').not.toBeNull();
    expect(Number(match?.[1])).toBeLessThan(SUPABASE_DEFAULT_JWT_EXPIRY_SECONDS);
  });

  it('enables the custom access token hook', () => {
    expect(CONFIG).toMatch(/^\[auth\.hook\.custom_access_token\]$/m);
    const stanza = CONFIG.slice(CONFIG.indexOf('[auth.hook.custom_access_token]'));
    expect(stanza).toMatch(/^enabled\s*=\s*true\s*$/m);
  });

  it('points the hook at the app schema, never at public', () => {
    // A hook in `public` would be a PostgREST RPC and would appear in the
    // generated types, so the schema is load-bearing for the schema-drift gate,
    // not a matter of taste.
    const match = /^uri\s*=\s*"pg-functions:\/\/postgres\/(\w+)\/custom_access_token_hook"\s*$/m.exec(
      CONFIG,
    );
    expect(match, 'the hook uri is not set in the documented form').not.toBeNull();
    expect(match?.[1]).toBe('app');
  });
});

const BOOTSTRAP = readFileSync(
  new URL('../../.github/workflows/bootstrap-platform-user.yml', import.meta.url),
  'utf8',
);

describe('the first-platform-user bootstrap cannot become a second one', () => {
  it('guards the insert with an emptiness check in the statement itself', () => {
    // OPEN-001's whole safety property. It is a `where not exists` inside the
    // SQL rather than a check in a script, so that once any platform_users row
    // exists the workflow is permanently inert. Deleting this clause is the
    // failure this assertion exists to catch — it would turn a one-time
    // bootstrap into a general-purpose way to mint super admins.
    expect(BOOTSTRAP).toMatch(/not exists\s*\(\s*select 1 from public\.platform_users\s*\)/i);
  });

  it('never creates an authentication identity, only labels one', () => {
    // The person must already have signed up through the ordinary flow. A
    // workflow that could create an auth user would be a credential factory.
    expect(BOOTSTRAP).not.toMatch(/insert\s+into\s+auth\.users/i);
  });
});
