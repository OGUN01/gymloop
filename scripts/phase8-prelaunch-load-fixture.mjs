/** Pure HARD-004 synthetic hierarchy planning. No Cloud or filesystem access. */
import { createHash } from 'node:crypto';
import { PHASE8_PRELAUNCH_LOAD_LIMITS } from '../packages/shared/src/config/constants.ts';

const {
  gymCount: GYM_COUNT, membersPerGym: MEMBERS_PER_GYM, checkInCount: CHECK_IN_COUNT,
  syntheticPlanDurationDays: PLAN_DAYS, syntheticPhoneDigits: PHONE_DIGITS,
  syntheticGymCodeHashChars: GYM_CODE_HASH_CHARS, syntheticGymCodeIndexWidth: GYM_CODE_INDEX_WIDTH,
} = PHASE8_PRELAUNCH_LOAD_LIMITS;
const MARKER_RE = /^PHASE8-LOAD-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function refuse(message) { throw new Error(`HARD-004 fixture planner: ${message}`); }
function uuidFrom(seed) {
  const hex = createHash('md5').update(seed, 'utf8').digest('hex');
  return hex.replace(/^(.{8})(.{4}).(.{3}).(.{3})(.{12})$/, '$1-$2-4$3-8$4-$5');
}
function plannedUuid(marker, kind, gymIndex, memberIndex) {
  const suffix = memberIndex === undefined ? `${gymIndex}` : `${gymIndex}:${memberIndex}`;
  return uuidFrom(`${marker}:${kind}:${suffix}`);
}
function exactKeys(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) refuse('expected a record.');
  const actual = Object.keys(value);
  const expected = new Set(keys);
  if (actual.length !== expected.size || actual.some((key) => !expected.has(key))) refuse('unexpected or missing record field.');
}
function assertPlan(plan) {
  exactKeys(plan, ['marker', 'gyms']);
  const expected = buildPrelaunchSyntheticPlan(plan.marker);
  if (JSON.stringify(plan) !== JSON.stringify(expected)) refuse('the complete recovered plan differs from its marker-derived identities.');
  return expected;
}
function sqlUuidArray(gyms) {
  return `ARRAY[${gyms.map((gym) => `'${gym.gymId}'::uuid`).join(', ')}]`;
}
function sqlMd5Uuid(expression) {
  return `(substring(${expression} from 1 for 8) || '-' || substring(${expression} from 9 for 4) || '-4' || substring(${expression} from 14 for 3) || '-8' || substring(${expression} from 18 for 3) || '-' || substring(${expression} from 21 for 12))::uuid`;
}

/** Reproducible planned IDs enable exact cleanup after process interruption. */
export function buildPrelaunchSyntheticPlan(marker) {
  if (typeof marker !== 'string' || !MARKER_RE.test(marker)) refuse('a fresh PHASE8-LOAD UUID marker is required.');
  const emailTag = marker.slice('PHASE8-LOAD-'.length).toLowerCase();
  const gyms = Array.from({ length: GYM_COUNT }, (_, gymIndex) => ({
    gymId: plannedUuid(marker, 'gym', gymIndex),
    branchId: plannedUuid(marker, 'branch', gymIndex),
    planId: plannedUuid(marker, 'plan', gymIndex),
    staffId: plannedUuid(marker, 'staff', gymIndex),
    email: `staff-${gymIndex}-${emailTag}@gymloop-load.invalid`,
    members: Array.from({ length: MEMBERS_PER_GYM }, (_, memberIndex) => ({
      memberId: plannedUuid(marker, 'member', gymIndex, memberIndex),
      membershipId: plannedUuid(marker, 'membership', gymIndex, memberIndex),
    })),
  }));
  return { marker, gyms };
}

/** One transaction, new marked rows only; Auth users must already exist. */
export function renderPrelaunchStageSql(plan, authBindings) {
  const canonical = assertPlan(plan);
  if (!Array.isArray(authBindings) || authBindings.length !== GYM_COUNT) refuse('exactly one Auth binding per gym is required.');
  const byEmail = new Map(); const userIds = new Set();
  for (const binding of authBindings) {
    exactKeys(binding, ['email', 'userId']);
    if (typeof binding.email !== 'string' || typeof binding.userId !== 'string' ||
        !UUID_RE.test(binding.userId) || byEmail.has(binding.email) || userIds.has(binding.userId)) {
      refuse('Auth bindings must have distinct, valid email and user IDs.');
    }
    byEmail.set(binding.email, binding.userId); userIds.add(binding.userId);
  }
  if (canonical.gyms.some((gym) => !byEmail.has(gym.email))) refuse('an Auth binding belongs to a foreign or missing synthetic email.');
  const fixtureValues = canonical.gyms.map((gym, index) =>
    `  (${index}, '${gym.gymId}'::uuid, '${gym.branchId}'::uuid, '${gym.planId}'::uuid, '${gym.staffId}'::uuid, '${byEmail.get(gym.email)}'::uuid, '${gym.email}')`).join(',\n');
  const gymIds = sqlUuidArray(canonical.gyms);
  const lastGym = canonical.gyms.at(-1);
  const lastMember = lastGym.members.at(-1);
  const memberHash = `md5('${canonical.marker}:member:' || f.gym_index::text || ':' || n.member_index::text)`;
  const membershipHash = `md5('${canonical.marker}:membership:' || f.gym_index::text || ':' || n.member_index::text)`;
  return `begin;
create temporary table phase8_load_fixture on commit drop as
select * from (values
${fixtureValues}
) as v(gym_index, gym_id, branch_id, plan_id, staff_id, auth_user_id, email);

insert into public.organizations (id, name, gym_code, status, tier, activated_at, timezone, currency)
select gym_id, '${canonical.marker} gym ' || gym_index::text,
  upper(substring(md5('${canonical.marker}') from 1 for ${GYM_CODE_HASH_CHARS})) || lpad((gym_index + 1)::text, ${GYM_CODE_INDEX_WIDTH}, '0'),
  'active', 'growth', now(), 'Asia/Kolkata', 'INR' from phase8_load_fixture;
insert into public.organization_settings (tenant_id)
select gym_id from phase8_load_fixture;
insert into public.branches (id, tenant_id, name, is_default)
select branch_id, gym_id, '${canonical.marker} branch', true from phase8_load_fixture;
insert into public.plans (id, tenant_id, name, duration_days, price_paise, currency)
select plan_id, gym_id, '${canonical.marker} zero-price test plan', ${PLAN_DAYS}, 0, 'INR' from phase8_load_fixture;
insert into public.staff (id, tenant_id, user_id, branch_id, role, full_name, email, is_active)
select staff_id, gym_id, auth_user_id, branch_id, 'front_desk', '${canonical.marker} synthetic staff', email, true from phase8_load_fixture;

create temporary table phase8_load_members on commit drop as
select f.gym_id, f.branch_id, f.plan_id, f.gym_index, n.member_index,
  ${sqlMd5Uuid(memberHash)} as member_id,
  ${sqlMd5Uuid(membershipHash)} as membership_id
from phase8_load_fixture f cross join lateral generate_series(0, ${MEMBERS_PER_GYM - 1}) as n(member_index);
insert into public.members (id, tenant_id, branch_id, full_name, phone, status)
select member_id, gym_id, branch_id, '${canonical.marker} member ' || gym_index::text || ':' || member_index::text,
  '+1' || lpad((gym_index * ${MEMBERS_PER_GYM} + member_index + 1)::text, ${PHONE_DIGITS}, '0'), 'active'
from phase8_load_members;
insert into public.memberships (id, tenant_id, member_id, plan_id, status, starts_on, ends_on, price_paise, discount_paise, currency, activated_at)
select membership_id, gym_id, member_id, plan_id, 'active',
  (now() at time zone 'Asia/Kolkata')::date - 1,
  (now() at time zone 'Asia/Kolkata')::date + ${PLAN_DAYS}, 0, 0, 'INR', now()
from phase8_load_members;

do $phase8_assert$
begin
  if (select count(*) from public.organizations where id = any(${gymIds})) <> ${GYM_COUNT}
     or (select count(*) from public.staff where tenant_id = any(${gymIds})) <> ${GYM_COUNT}
     or (select count(*) from public.members where tenant_id = any(${gymIds})) <> ${CHECK_IN_COUNT}
     or (select count(*) from public.memberships where tenant_id = any(${gymIds})) <> ${CHECK_IN_COUNT}
     or not exists (select 1 from public.members where tenant_id = '${lastGym.gymId}'::uuid and id = '${lastMember.memberId}'::uuid) then
    raise exception 'HARD-004 staged counts or final planned member do not match';
  end if;
end;
$phase8_assert$;
commit;`;
}

/** Exact planned-tenant deletion, safe when staging committed only partially. */
export function renderPrelaunchCleanupSql(plan) {
  const canonical = assertPlan(plan);
  const gymIds = sqlUuidArray(canonical.gyms);
  const tables = ['attendance', 'memberships', 'members', 'plans', 'staff', 'branches', 'organization_settings'];
  const deletion = tables.map((table) => `delete from public.${table} where tenant_id = any(${gymIds});`).join('\n');
  const remainder = tables.map((table) => `(select count(*) from public.${table} where tenant_id = any(${gymIds})) <> 0`).join('\n     or ');
  return `begin;
do $phase8_guard$
begin
  if exists (select 1 from public.organizations where id = any(${gymIds}) and name not like '${canonical.marker} gym %') then
    raise exception 'HARD-004 planned gym identity is no longer marker-owned';
  end if;
end;
$phase8_guard$;
${deletion}
delete from public.organizations where id = any(${gymIds});
do $phase8_assert$
begin
  if (select count(*) from public.organizations where id = any(${gymIds})) <> 0
     or ${remainder} then
    raise exception 'HARD-004 synthetic database identities remain';
  end if;
end;
$phase8_assert$;
commit;`;
}

/** Parse only a single linked Cloud query row; never infer size from text. */
export function parseLinkedDatabaseSize(raw) {
  if (typeof raw !== 'string' || raw.trim() === '') refuse('linked size query returned no JSON.');
  let data;
  try { data = JSON.parse(raw); } catch { refuse('linked size query returned malformed JSON.'); }
  if (!Array.isArray(data)) {
    if (!data || typeof data !== 'object' || Object.hasOwn(data, 'error') || !Array.isArray(data.rows)) refuse('linked size query failed.');
    data = data.rows;
  }
  if (data.length !== 1) refuse('linked size query must return one row.');
  exactKeys(data[0], ['database_bytes']);
  const bytes = data[0].database_bytes;
  if (!Number.isSafeInteger(bytes) || bytes < 0) refuse('linked database size is not a safe nonnegative integer.');
  return bytes;
}
