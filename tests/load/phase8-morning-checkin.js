import http from 'k6/http';
import { check, fail } from 'k6';

const GYM_COUNT = 100;
const MEMBERS_PER_GYM = 500;
const TOTAL_MEMBER_CHECK_INS = 50_000;
const MORNING_SPIKE_VUS = 100;
const DENIED_STATUS_CODES = [401, 403, 404];
const PRODUCTION_PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const REQUIRED_CONFIRMATION = 'NON_PRODUCTION_LOAD_APPROVED';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HTTP_SUCCESS_MIN = 200;
const HTTP_SUCCESS_MAX = 299;

function required(name) {
  const value = __ENV[name];
  if (typeof value !== 'string' || value.trim() === '') fail(`HARD-004 missing ${name}`);
  return value;
}

function boundedIndex(iteration, size) {
  return iteration % size;
}

function requiredOrigin(name) {
  const value = required(name);
  let url;
  try { url = new URL(value); } catch { fail(`HARD-004 ${name} must be a valid HTTPS origin.`); }
  if (url.protocol !== 'https:' || url.username !== '' || url.password !== '' ||
      url.pathname !== '/' || url.search !== '' || url.hash !== '' || url.hostname.includes(PRODUCTION_PROJECT_REF)) {
    fail(`HARD-004 ${name} must be an isolated HTTPS origin-only non-production target.`);
  }
  return url.origin;
}

function requireNonProductionIdentity() {
  const projectRef = required('PHASE8_LOAD_PROJECT_REF');
  const observedApiProjectRef = required('PHASE8_LOAD_OBSERVED_API_PROJECT_REF');
  const observedSupabaseProjectRef = required('PHASE8_LOAD_OBSERVED_SUPABASE_PROJECT_REF');
  const credentialProjectRef = required('PHASE8_LOAD_CREDENTIAL_PROJECT_REF');
  if (projectRef === PRODUCTION_PROJECT_REF || observedApiProjectRef !== projectRef || observedSupabaseProjectRef !== projectRef ||
      credentialProjectRef !== projectRef || required('PHASE8_LOAD_CREDENTIAL_KIND') !== 'non-production' ||
      required('PHASE8_LOAD_CONFIRMATION') !== REQUIRED_CONFIRMATION) fail('HARD-004 requires matching observed non-production project identity and confirmation.');
  return projectRef;
}

function tenantFixtures() {
  try {
    return JSON.parse(required('PHASE8_LOAD_TENANTS_JSON'));
  } catch {
    fail('HARD-004 tenant fixtures must be valid JSON.');
  }
}

function validatedFixtures(fixtures) {
  if (!Array.isArray(fixtures) || fixtures.length !== GYM_COUNT) fail('HARD-004 requires exactly 100 isolated gym fixtures.');
  const gymIds = new Set(); const tokens = new Set(); const memberIds = new Set();
  for (const fixture of fixtures) {
    if (fixture === null || typeof fixture !== 'object' || typeof fixture.gymId !== 'string' || fixture.gymId.trim() === '' ||
        typeof fixture.token !== 'string' || fixture.token.trim() === '' ||
        !Array.isArray(fixture.memberIds) || !Array.isArray(fixture.ownedMemberIds) || fixture.memberIds.length !== MEMBERS_PER_GYM ||
        fixture.ownedMemberIds.length !== MEMBERS_PER_GYM || gymIds.has(fixture.gymId) || tokens.has(fixture.token)) {
      fail('HARD-004 fixture identity is incomplete or duplicated.');
    }
    gymIds.add(fixture.gymId); tokens.add(fixture.token);
    const owned = new Set(fixture.ownedMemberIds); const current = new Set(fixture.memberIds);
    const ownedMemberIdsAreNonblank = [...owned].every((memberId) => typeof memberId === 'string' && memberId.trim() !== '');
    const currentMemberIdsAreNonblank = [...current].every((memberId) => typeof memberId === 'string' && memberId.trim() !== '');
    if (owned.size !== MEMBERS_PER_GYM || current.size !== MEMBERS_PER_GYM || !ownedMemberIdsAreNonblank ||
        !currentMemberIdsAreNonblank || [...owned].some((memberId) => !current.has(memberId))) {
      fail('HARD-004 fixture members must be unique and exactly owned by their gym.');
    }
    for (const memberId of current) { if (memberIds.has(memberId)) fail('HARD-004 member identities must be globally unique.'); memberIds.add(memberId); }
  }
  return fixtures;
}

function checkInEventId(gymIndex, memberIndex) {
  const ordinal = gymIndex * MEMBERS_PER_GYM + memberIndex;
  return `${runId.slice(0, -4)}${ordinal.toString(16).padStart(4, '0')}`;
}

function crossTenantEventId() {
  return `${runId.slice(0, -4)}ffff`;
}

const projectRef = requireNonProductionIdentity();
const apiUrl = requiredOrigin('PHASE8_LOAD_API_URL');
const supabaseUrl = requiredOrigin('PHASE8_LOAD_SUPABASE_URL');
const supabaseAnonKey = required('PHASE8_LOAD_SUPABASE_ANON_KEY');
const p95Ms = Number(required('PHASE8_LOAD_P95_MS'));
const runId = required('PHASE8_LOAD_RUN_ID');
const tenants = validatedFixtures(tenantFixtures());

if (supabaseUrl !== `https://${projectRef}.supabase.co`) fail('HARD-004 Supabase origin must bind exactly to the non-production project reference.');
if (!UUID.test(runId)) fail('HARD-004 PHASE8_LOAD_RUN_ID must be a UUID.');

if (!Number.isFinite(p95Ms) || p95Ms <= 0) fail('HARD-004 requires a positive caller-approved p95 threshold.');
if (!Array.isArray(tenants) || tenants.length !== GYM_COUNT || tenants.some((tenant) =>
  tenant === null || typeof tenant !== 'object' || typeof tenant.token !== 'string' ||
  !Array.isArray(tenant.memberIds) || tenant.memberIds.length !== MEMBERS_PER_GYM ||
  !tenant.memberIds.every((memberId) => typeof memberId === 'string' && memberId.trim() !== ''))) {
  fail('HARD-004 requires exactly 100 isolated tenant fixtures with 500 member ids each.');
}

const gymA = tenants[0];
const gymB = tenants[1];

export const options = {
  scenarios: {
    morning_check_in_spike: {
      executor: 'per-vu-iterations',
      vus: MORNING_SPIKE_VUS,
      iterations: TOTAL_MEMBER_CHECK_INS / MORNING_SPIKE_VUS,
      maxDuration: '30m',
    },
    cross_tenant_read_denial: { executor: 'shared-iterations', exec: 'cross_tenant_read_denial', vus: 1, iterations: 1, startTime: '0s' },
    cross_tenant_mutation_denial: { executor: 'shared-iterations', exec: 'cross_tenant_mutation_denial', vus: 1, iterations: 1, startTime: '0s' },
  },
  thresholds: {
    http_req_duration: [`p(95)<${p95Ms}`],
    checks: ['rate==1'],
  },
};

function appAuth(token) {
  return { headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' } };
}

function supabaseAuth(token) {
  return { headers: { apikey: supabaseAnonKey, authorization: `Bearer ${token}` } };
}

function checkIn(memberId, token, requestKey) {
  return http.post(`${apiUrl}/api/check-in`, JSON.stringify({ memberId, reason: 'phase8 load check-in', clientEventId: requestKey }), appAuth(token));
}

export default function () {
  const gymIndex = boundedIndex(__VU - 1, GYM_COUNT);
  const memberIndex = boundedIndex(__ITER, MEMBERS_PER_GYM);
  const tenant = tenants[gymIndex];
  const response = checkIn(tenant.memberIds[memberIndex], tenant.token, checkInEventId(gymIndex, memberIndex));
  check(response, { 'morning check-in is acknowledged': (result) => result.status >= 200 && result.status < 300 });
}

export function cross_tenant_read_denial() {
  const response = http.get(`${supabaseUrl}/rest/v1/members?id=eq.${gymB.memberIds[0]}`, supabaseAuth(gymA.token));
  check(response, { 'cross-tenant member read is denied': (result) => DENIED_STATUS_CODES.includes(result.status) || result.body === '[]' });
}

export function cross_tenant_mutation_denial() {
  const response = checkIn(gymB.memberIds[0], gymA.token, crossTenantEventId());
  check(response, { 'cross-tenant check-in mutation is denied': (result) => result.status < HTTP_SUCCESS_MIN || result.status > HTTP_SUCCESS_MAX });
}
