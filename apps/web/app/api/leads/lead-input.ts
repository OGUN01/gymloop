import { Constants } from '@gymloop/db';
import { gymWallClockFormatter, offsetInstantFromGymWallTime } from '@gymloop/shared';
import { apiFail, PG_INSUFFICIENT_PRIVILEGE, staffJson, type StaffSession } from '../../../lib/api';
import { UUID_PATTERN } from '../../../lib/keyset';
import { FRONT_OFFICE_ROLES, type LeadDetail, type LeadSource, type LeadStage } from '../../../lib/leads';

/**
 * The leads routes' shared half: the prologue every route runs (front-office
 * session, lead reference, body, command), the one shape in which an RPC is
 * invoked, strict body parsing, result validation, and the contract's error
 * table. It sits beside the handlers rather than in `packages/shared` because
 * `apps/web` has no zod and the contract's payloads are route commands, not
 * cross-package vocabulary — the same split the add-on handlers draw between
 * `lib/api.ts` and their own local mapping.
 *
 * Nothing here trusts a caller-owned fact it did not check: stage, source and
 * outcome come from the generated catalogue, ids from `UUID_PATTERN`, and a
 * payload with an unknown key is refused whole rather than partially read.
 */

/**
 * Statuses by name, as in `lib/api.ts`, plus the two success statuses that
 * file does not need: a created lead answers 201 and a replay answers 200.
 */
const STATUS = {
  ok: 200,
  created: 201,
  bad_request: 400,
  unauthorized: 401,
  forbidden: 403,
  not_found: 404,
  conflict: 409,
  unprocessable: 422,
  server_error: 500,
} as const;

type LeadStatus = keyof typeof STATUS;

const JSON_HEADERS = { 'content-type': 'application/json' } as const;

/** A success envelope, at the one of the two success statuses a lead write can answer. */
export function leadOk(status: 'ok' | 'created', data: unknown): Response {
  return new Response(JSON.stringify({ ok: true, data }), { status: STATUS[status], headers: JSON_HEADERS });
}

/**
 * A failure envelope. Unlike `apiFail()` this can carry the one extra fact
 * some lead conflicts need — the current revision on `stale_lead`, the four
 * member facts on `link_required` — because a client cannot resolve either
 * conflict without them.
 */
function leadFail(
  status: Exclude<LeadStatus, 'ok' | 'created'>,
  code: string,
  message: string,
  extra?: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify({ ok: false, error: { code, message, ...extra } }), {
    status: STATUS[status],
    headers: JSON_HEADERS,
  });
}

/** What a lead RPC answers, narrowed to the fields the handlers read. */
export type LeadRpcError = { code: string; message: string; details?: string | null };

type LeadIdContext = { params: Promise<{ leadId: string }> };
type LeadCommandRead<T, Id> = { failure: Response } | (StaffSession & { leadId: Id; command: T });

/**
 * The prologue every leads route runs, in the one order the contract allows:
 * identify the caller, refuse a lead reference that is not an id, read the
 * body, parse the command. Each route used to spell this out and `jscpd` was
 * right to call the copies clones — an order that must not vary is exactly
 * the thing to write once, and three copies were three places for one route
 * to drift into reading the body before it knows who is asking.
 *
 * Front office only, and the identity check precedes the body parse, so an
 * unauthenticated or unpermitted caller learns nothing from what the route
 * does with its payload. The `invalidMessage` is the caller's, because only
 * the route knows which facts its command names.
 */
export async function readLeadCommand<T>(
  request: Request,
  context: LeadIdContext,
  parse: (payload: unknown) => T | null,
  invalidMessage: string,
): Promise<LeadCommandRead<T, string>>;
export async function readLeadCommand<T>(
  request: Request,
  context: null,
  parse: (payload: unknown) => T | null,
  invalidMessage: string,
): Promise<LeadCommandRead<T, null>>;
export async function readLeadCommand<T>(
  request: Request,
  context: LeadIdContext | null,
  parse: (payload: unknown) => T | null,
  invalidMessage: string,
): Promise<LeadCommandRead<T, string | null>> {
  const caller = await staffJson(request, FRONT_OFFICE_ROLES, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return { failure: caller.failure };

  let leadId: string | null = null;
  if (context !== null) {
    leadId = (await context.params).leadId;
    if (!UUID_PATTERN.test(leadId)) {
      return { failure: apiFail('bad_request', 'invalid_request', 'That lead reference is not a valid id.') };
    }
  }

  const command = parse(caller.payload);
  if (command === null) {
    return { failure: apiFail('bad_request', 'invalid_request', invalidMessage) };
  }

  return {
    supabase: caller.supabase,
    userId: caller.userId,
    tenantId: caller.tenantId,
    staffId: caller.staffId,
    role: caller.role,
    leadId,
    command,
  };
}

/**
 * One lead RPC invocation, through the same narrow local cast every leads
 * route uses for functions that are not in the generated types yet. The
 * caller builds the exact `p_*` arguments; this owns only the cast and the
 * honest `{ data, error }` shape, so three routes cannot drift into three
 * slightly different ideas of what an RPC answer looks like.
 */
export async function callLeadRpc<A extends Record<string, unknown>>(
  supabase: StaffSession['supabase'],
  name: string,
  args: A,
): Promise<{ data: unknown; error: LeadRpcError | null }> {
  const writer = supabase as unknown as {
    rpc(name: string, args: A): Promise<{ data: unknown; error: LeadRpcError | null }>;
  };
  return await writer.rpc(name, args);
}

/** Byte-identical to the database's `leads_phone_format_chk` — see the comment at its use. */
const E164_PHONE = /^\+[1-9][0-9]{7,14}$/;
const TRIAL_LOCAL = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$/;
const ALLOWED_OUTCOMES = ['created_member', 'linked_existing'] as const;

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}

/** Collapses runs of whitespace to single spaces and trims the ends. */
function canonicalText(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

/**
 * A caller-supplied string: canonical nonempty text, or null when blank.
 * An empty optional field means "no value", not "the empty string" — the
 * database stores null and the RPC contract agrees.
 */
function optionalText(value: unknown): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'string') return undefined;
  const canonical = canonicalText(value);
  return canonical === '' ? null : canonical;
}

function catalogueStage(value: unknown): LeadStage | undefined {
  return typeof value === 'string' &&
    (Constants.public.Enums.lead_stage as readonly string[]).includes(value)
    ? (value as LeadStage)
    : undefined;
}

function catalogueSource(value: unknown): LeadSource | undefined {
  return typeof value === 'string' &&
    (Constants.public.Enums.lead_source as readonly string[]).includes(value)
    ? (value as LeadSource)
    : undefined;
}

function hasOnly(payload: Record<string, unknown>, allowed: readonly string[]): boolean {
  return Object.keys(payload).every((key) => allowed.includes(key));
}

function hasAll(payload: Record<string, unknown>, required: readonly string[]): boolean {
  return required.every((key) => payload[key] !== undefined);
}

/**
 * The seven editable lead facts creation and update share — branch, person,
 * contact and assignment — read all-or-nothing. A partial read would let one
 * bad field past the route to fail at the RPC with a less honest answer, and
 * both commands refusing a field for a different reason is a client the
 * contract changed under.
 */
function editableLeadFacts(payload: Record<string, unknown>): {
  branchId: string;
  fullName: string;
  phone: string;
  email: string | null;
  source: LeadSource;
  assignedToStaffId: string | null;
  notes: string | null;
} | null {
  if (!isUuid(payload.branchId)) return null;
  const fullName = optionalText(payload.fullName);
  if (fullName === null || fullName === undefined) return null;
  // The frozen route contract requires refusing a non-E.164 phone BEFORE the
  // RPC is invoked, so this copy must exist — but it is kept byte-identical to
  // the governing `leads_phone_format_chk` (`^\+[1-9][0-9]{7,14}$`) so the two
  // can only drift together, and a phone this accepts is exactly what the
  // database accepts. `MemberForm` needs no copy because nothing pins that
  // refusal client-side; this route's tests do.
  if (typeof payload.phone !== 'string' || !E164_PHONE.test(payload.phone)) return null;
  const source = catalogueSource(payload.source);
  if (source === undefined) return null;

  // The contract marks the three optional facts `email?: string | null`:
  // an omitted optional is accepted and stored as null ("no value"), while a
  // present value of the wrong type is still refused whole. `update_details`
  // keeps requiring all seven facts (a partial edit would race two writers
  // into one row), so this leniency is creation's alone.
  const email = payload.email === undefined ? null : optionalText(payload.email);
  const assignedToStaffId = payload.assignedToStaffId === undefined ? null : optionalText(payload.assignedToStaffId);
  const notes = payload.notes === undefined ? null : optionalText(payload.notes);
  if (email === undefined || assignedToStaffId === undefined || notes === undefined) return null;
  if (assignedToStaffId !== null && !isUuid(assignedToStaffId)) return null;

  return { branchId: payload.branchId, fullName, phone: payload.phone, email, source, assignedToStaffId, notes };
}

export type CreateLeadCommand = {
  requestKey: string;
  branchId: string;
  fullName: string;
  phone: string;
  email: string | null;
  source: LeadSource;
  assignedToStaffId: string | null;
  notes: string | null;
};

/**
 * The eight caller-owned creation facts and nothing else. `stage`, `tenantId`,
 * `createdAt` and idempotency aliases are refused rather than ignored: a body
 * that tries to set any of them is a client the contract changed under, and
 * silently accepting the rest of it would return a lead the caller believes
 * has different facts than it does.
 */
export function parseCreateLead(payload: unknown): CreateLeadCommand | null {
  if (!isObject(payload)) return null;
  const allowed = ['requestKey', 'branchId', 'fullName', 'phone', 'email', 'source', 'assignedToStaffId', 'notes'];
  if (!hasOnly(payload, allowed)) return null;
  if (!hasAll(payload, ['requestKey', 'branchId', 'fullName', 'phone', 'source'])) return null;
  if (!isUuid(payload.requestKey)) return null;

  const facts = editableLeadFacts(payload);
  if (facts === null) return null;
  return { requestKey: payload.requestKey, ...facts };
}

export type LeadCommand =
  | { command: 'update_details'; expectedRevision: string; branchId: string; fullName: string; phone: string; email: string | null; source: LeadSource; assignedToStaffId: string | null; notes: string | null }
  | { command: 'transition'; expectedRevision: string; toStage: Exclude<LeadStage, 'converted'>; trialLocal: string | null; lostReason: string | null };

/**
 * One lead, one of two commands. `update_details` carries the full editable
 * fact set (a partial edit would race two writers into one row); `transition`
 * carries a stage move and its evidence. A body mixing the two shapes is
 * refused whole, and `converted` is not a transition target — conversion has
 * its own command, its own idempotency and its own atomicity, and letting it
 * in here would let a caller skip all three.
 */
export function parseLeadCommand(payload: unknown): LeadCommand | null {
  if (!isObject(payload)) return null;

  if (payload.command === 'update_details') {
    const required = ['command', 'expectedRevision', 'branchId', 'fullName', 'phone', 'email', 'source', 'assignedToStaffId', 'notes'];
    if (!hasOnly(payload, required) || !hasAll(payload, required)) return null;
    if (!isUuid(payload.expectedRevision)) return null;
    const facts = editableLeadFacts(payload);
    if (facts === null) return null;
    return { command: 'update_details', expectedRevision: payload.expectedRevision, ...facts };
  }

  if (payload.command === 'transition') {
    const allowed = ['command', 'expectedRevision', 'toStage', 'trialLocal', 'lostReason'];
    if (!hasOnly(payload, allowed) || !hasAll(payload, ['command', 'expectedRevision', 'toStage'])) return null;
    if (!isUuid(payload.expectedRevision)) return null;
    const toStage = catalogueStage(payload.toStage);
    if (toStage === undefined || toStage === 'converted') return null;
    let trialLocal: string | null = null;
    if (payload.trialLocal !== undefined && payload.trialLocal !== null) {
      if (typeof payload.trialLocal !== 'string' || !TRIAL_LOCAL.test(payload.trialLocal)) return null;
      trialLocal = payload.trialLocal;
    }
    let lostReason: string | null = null;
    if (payload.lostReason !== undefined && payload.lostReason !== null) {
      if (typeof payload.lostReason !== 'string') return null;
      lostReason = canonicalText(payload.lostReason);
    }
    return { command: 'transition', expectedRevision: payload.expectedRevision, toStage, trialLocal, lostReason };
  }

  return null;
}

export type ConvertLeadCommand =
  | { mode: 'create'; requestKey: string; expectedRevision: string }
  | { mode: 'link_existing'; requestKey: string; expectedRevision: string; memberId: string };

/**
 * The conversion command. Create mode names no member (choosing one would
 * defeat the duplicate check the RPC exists to run); link mode must name one,
 * because an unnamed link is exactly the automatic conversion the desk is
 * being asked to confirm. `outcome` is server-owned and its presence in a
 * request is refused: a caller forging it is trying to skip the transaction.
 */
export function parseConvertLead(payload: unknown): ConvertLeadCommand | null {
  if (!isObject(payload)) return null;
  if (!hasOnly(payload, ['requestKey', 'expectedRevision', 'mode', 'memberId'])) return null;
  if (!isUuid(payload.requestKey) || !isUuid(payload.expectedRevision)) return null;

  if (payload.mode === 'create') {
    if (payload.memberId !== undefined && payload.memberId !== null) return null;
    return { mode: 'create', requestKey: payload.requestKey, expectedRevision: payload.expectedRevision };
  }
  if (payload.mode === 'link_existing') {
    if (!isUuid(payload.memberId)) return null;
    return { mode: 'link_existing', requestKey: payload.requestKey, expectedRevision: payload.expectedRevision, memberId: payload.memberId };
  }
  return null;
}

export type CreateLeadResult = { leadId: string; revision: string; replayed: boolean };

/** A creation result is only accepted with both ids and the replay flag present. */
export function createLeadResult(data: unknown): CreateLeadResult | null {
  if (!isObject(data)) return null;
  if (!isUuid(data.leadId) || !isUuid(data.revision) || typeof data.replayed !== 'boolean') return null;
  return { leadId: data.leadId, revision: data.revision, replayed: data.replayed };
}

/**
 * The accepted lead an edit or transition returns. The contract pins its
 * shape; a result that does not match is treated as a failure rather than
 * passed through — an RPC that answers nonsense must not be turned into a
 * success the desk then acts on.
 */
export function acceptedLead(data: unknown): LeadDetail | null {
  if (!isObject(data) || !isObject(data.lead)) return null;
  const lead = data.lead;
  if (!isUuid(lead.id) || !isUuid(lead.revision)) return null;
  if (typeof lead.fullName !== 'string' || lead.fullName === '') return null;
  if (typeof lead.phone !== 'string' || lead.phone === '') return null;
  if (!isUuid(lead.branchId)) return null;
  if (catalogueStage(lead.stage) === undefined || catalogueSource(lead.source) === undefined) return null;
  return lead as unknown as LeadDetail;
}

export type ConvertLeadResult = {
  leadId: string;
  memberId: string;
  outcome: (typeof ALLOWED_OUTCOMES)[number];
  revision: string;
  replayed: boolean;
};

/** A conversion result needs both ids, a catalogue outcome and the replay flag. */
export function convertLeadResult(data: unknown): ConvertLeadResult | null {
  if (!isObject(data)) return null;
  if (!isUuid(data.leadId) || !isUuid(data.memberId) || !isUuid(data.revision)) return null;
  if (typeof data.replayed !== 'boolean') return null;
  if (typeof data.outcome !== 'string' || !(ALLOWED_OUTCOMES as readonly string[]).includes(data.outcome)) return null;
  return { leadId: data.leadId, memberId: data.memberId, outcome: data.outcome as ConvertLeadResult['outcome'], revision: data.revision, replayed: data.replayed };
}

/** The revision the caller should retry against, when the RPC reports a stale write. */
export function staleRevision(data: unknown): string | null {
  if (!isObject(data) || data.staleLead !== true) return null;
  return isUuid(data.currentRevision) ? data.currentRevision : null;
}

/** The RPC's "refuse without facts" shape for a same-phone member that cannot be linked. */
export function memberUnavailable(data: unknown): boolean {
  return isObject(data) && data.memberUnavailable === true;
}

/**
 * The contract's error table for `create_lead`, `update_lead` and
 * `transition_lead`. Every code maps to one honest outcome; an unknown
 * SQLSTATE is a 500 rather than a guess, because inventing a success shape
 * for an unhandled database failure is how a lost write gets reported as done.
 */
export function leadWriteFailure(error: LeadRpcError): Response {
  switch (error.code) {
    case '40001':
    case '40P01':
      return leadFail('conflict', 'retryable', 'Another change to this lead just landed. Try again.');
    case 'P0002':
      return leadFail('not_found', 'not_found', 'That lead is not available.');
    case PG_INSUFFICIENT_PRIVILEGE:
      return leadFail('forbidden', 'not_permitted', 'Your staff role cannot perform this action.');
    case 'GL059':
      return leadFail('conflict', 'invalid_transition', 'A lead cannot move to that stage from where it is.');
    case 'GL060':
      return leadFail('unprocessable', 'invalid_lead_facts', 'That stage change needs different lead facts.');
    case 'GL062':
      return leadFail('conflict', 'idempotency_conflict', 'This request key was already used for a different change.');
    default:
      return leadFail('server_error', 'operation_failed', 'The change could not be saved. Nothing was written.');
  }
}

type LinkRequiredMember = { memberId: string; fullName: string; phone: string; status: string };

/**
 * The conversion error table. `GL061` is the one error whose payload carries
 * facts: exactly the four the contract allows the desk to see about an
 * eligible same-gym member, read from the error's DETAIL. A DETAIL that does
 * not parse still answers `link_required` — without the member, because
 * unparseable is not the same as disclosable.
 */
export function convertLeadFailure(error: LeadRpcError): Response {
  if (error.code === 'GL061') {
    let member: LinkRequiredMember | null = null;
    if (typeof error.details === 'string') {
      try {
        const parsed: unknown = JSON.parse(error.details);
        if (isObject(parsed) && isUuid(parsed.memberId) &&
          typeof parsed.fullName === 'string' && parsed.fullName !== '' &&
          typeof parsed.phone === 'string' && parsed.phone !== '' &&
          typeof parsed.status === 'string' && parsed.status !== '') {
          member = { memberId: parsed.memberId, fullName: parsed.fullName, phone: parsed.phone, status: parsed.status };
        }
      } catch {
        member = null;
      }
    }
    return leadFail('conflict', 'link_required', 'An existing member already owns this phone. Link the lead to that member instead.', member === null ? undefined : { member });
  }
  return leadWriteFailure(error);
}

/** The stale-write conflict, with the revision the caller should retry against. */
export function staleLeadFailure(currentRevision: string): Response {
  return leadFail('conflict', 'stale_lead', 'This lead changed while you were working on it.', { currentRevision });
}

/**
 * The generic same-phone conflict: a member exists but cannot be linked, and
 * the response discloses nothing about them — not the id, not the name —
 * because "unavailable" is all the desk is entitled to learn from a refusal.
 */
export function memberUnavailableFailure(): Response {
  return leadFail('conflict', 'member_unavailable', 'That phone belongs to a member who cannot be linked right now.');
}

function zonedWallTime(instant: string, timezone: string): string | null {
  const formatter = gymWallClockFormatter(timezone);
  if (formatter === null) return null;
  const parts = new Map(formatter.formatToParts(new Date(instant)).map((part) => [part.type, part.value]));
  const year = parts.get('year');
  const month = parts.get('month');
  const day = parts.get('day');
  const hour = parts.get('hour');
  const minute = parts.get('minute');
  const second = parts.get('second');
  const zone = parts.get('timeZoneName');
  if (!year || !month || !day || !hour || !minute || !second || !zone) return null;

  const offset = zone === 'GMT' ? '+00:00' : zone.replace(/^GMT/, '');
  if (!/^[+-][0-9]{2}:[0-9]{2}$/.test(offset)) return null;
  return `${year}-${month}-${day}T${hour}:${minute}:${second}${offset}`;
}

/**
 * One gym-local wall time to the instant it names, rendered as that same wall
 * time with its real UTC offset — `2026-09-20T10:00+05:30`, never a shifted
 * clock time and never a bare Z. The uniqueness resolution (skipped and
 * ambiguous DST wall times) is `offsetInstantFromGymWallTime`'s; this adds
 * only the offset-bearing rendering the RPC argument is specified to carry.
 * Null means the wall time does not name exactly one instant, and the caller
 * refuses rather than guessing.
 */
export function trialInstantAt(trialLocal: string, timezone: string): string | null {
  const instant = offsetInstantFromGymWallTime(trialLocal, timezone);
  if (instant === null) return null;
  return zonedWallTime(instant, timezone);
}
