import { createHash } from 'node:crypto';
import { apiFail, staffSession } from '../../../lib/api';
import {
  REPORT_DATASETS,
  buildReportCsv,
  parseReportExportRequest,
  reportExportFilename,
  validatePaymentMoney,
  type ReportExportMeta,
} from '../../../lib/report-exports';
import { DEFAULT_TIMEZONE, RPE_LIMITS, formatMoney } from '@gymloop/shared';

/**
 * RPE-001…009 (CSV-first delivery) — the one synchronous CSV download route.
 *
 * Order matters and is contractual: the same-origin check and the transport
 * body cap precede authentication (a body-size refusal may precede auth but
 * reveals no source facts); the owner gate precedes parameter validation, so a
 * refused role learns nothing about targets; validation precedes the single
 * bounded snapshot read; the `report_export.prepared` audit precedes any byte
 * leaving the database and `report_export.released` precedes the first byte of
 * the response. Every failure is an `apiFail` envelope — never a CSV-shaped
 * error body.
 *
 * The snapshot read is one bounded invoker data operation
 * (`export_report_snapshot`) under the original caller's session client — the
 * frozen architecture's "one bounded invoker data operation per artifact". The
 * operation's SQL side (rows/count/stamps payload with the gym-validated zone)
 * and the narrow audit-append helper are flagged gaps: until their migration
 * lands, an unavailable operation fails closed here (500), and the stamps the
 * route derives itself use `DEFAULT_TIMEZONE` — the same documented fallback
 * the registry records for `deskTime`, never a silent zone guess from data.
 */

export const runtime = 'nodejs';

/** The two SQL operations this route needs (`export_report_snapshot`,
 * `append_report_export_event`) are the flagged gaps in the frozen CSV-first
 * delivery: their defining migration has not landed, so the generated client's
 * rpc-name union does not know them yet. One narrow alias here — the union
 * widens naturally after CI applies that migration and types regenerate. */
type SnapshotClient = {
  rpc: (fnName: string, args?: Record<string, unknown>) => Promise<{
    data: unknown;
    error: { code?: string; message?: string } | null;
  }>;
};

export async function POST(request: Request): Promise<Response> {
  const startedAt = Date.now();
  const origin = request.headers.get('origin');
  if (origin !== null && origin !== new URL(request.url).origin) {
    return apiFail('forbidden', 'cross_origin', 'This export endpoint accepts same-origin requests only.');
  }

  const declaredLength = Number(request.headers.get('content-length') ?? '0');
  if (Number.isFinite(declaredLength) && declaredLength > RPE_LIMITS.bodyMaxBytes) {
    return apiFail('payload_too_large', 'body_too_large', 'The export request body is too large.');
  }

  const sessionResult = await staffSession(['gym_owner'], { completeWrongAudience: 'forbidden' }, request);
  if ('failure' in sessionResult) return sessionResult.failure;
  const session = sessionResult.session;

  // The declared content-length is also checked after the read: a chunked
  // transfer announces no length, so the decoded byte count is the honest cap.
  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).byteLength > RPE_LIMITS.bodyMaxBytes) {
    return apiFail('payload_too_large', 'body_too_large', 'The export request body is too large.');
  }
  let parsedBody: unknown;
  try {
    parsedBody = JSON.parse(rawBody) as unknown;
  } catch {
    return apiFail('bad_request', 'malformed_body', 'The request body was not JSON.');
  }

  const parsed = parseReportExportRequest(parsedBody);
  if ('error' in parsed) return apiFail('bad_request', 'invalid_request', parsed.error);
  const { dataset, from, through, branchId } = parsed.request;

  if (branchId !== null) {
    // RPE-002 — one visibility read under the caller's RLS. Unknown, foreign
    // and policy-hidden branches are deliberately indistinguishable here.
    const { data: branchRows, error: branchError } = await session.supabase
      .from('branches')
      .select('id')
      .eq('id', branchId);
    const visible = !branchError && Array.isArray(branchRows) && branchRows.length > 0;
    if (!visible) {
      return apiFail('not_found', 'request_unavailable', 'That branch is not available for export.');
    }
  }

  // RPE-003 — the complete generation deadline bounds the snapshot read: an
  // operation that has not answered inside it releases no file.
  let timedOut = false;
  let deadlineTimer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    deadlineTimer = setTimeout(() => {
      timedOut = true;
      reject(new Error('export_deadline_exceeded'));
    }, RPE_LIMITS.generationDeadlineMs);
  });
  const snapshot = await Promise.race([
    (session.supabase as unknown as SnapshotClient).rpc('export_report_snapshot', {
      p_dataset: dataset,
      p_from: from,
      p_through: through,
      p_branch_id: branchId,
      p_row_cap: RPE_LIMITS.csvMaxRows + 1,
    }),
    deadline,
  ])
    .finally(() => { if (deadlineTimer !== undefined) clearTimeout(deadlineTimer); })
    .catch(() => ({ data: null, error: { code: timedOut ? 'EXPORT_DEADLINE' : 'SNAPSHOT_ERROR' } }));
  const { data, error } = snapshot;
  if (error !== null) {
    if (error.code === 'EXPORT_DEADLINE') {
      return apiFail('server_error', 'export_timeout', 'The export took too long to generate. Narrow the date range and try again.');
    }
    if (error.code === '42501') {
      return branchId !== null
        ? apiFail('not_found', 'request_unavailable', 'That branch is not available for export.')
        : apiFail('forbidden', 'not_permitted', 'Your account cannot read these records.');
    }
    return apiFail('server_error', 'operation_failed', 'The export could not be read. Try again in a moment.');
  }

  // The operation's production contract is a payload object carrying rows and
  // the validated stamps; a bare row array is the documented pre-migration
  // shape, for which the route derives the stamps itself (see module comment).
  const payload = data as { rows?: unknown[]; timezone?: string } | unknown[] | null;
  const rows = (Array.isArray(payload) ? payload : (payload?.rows ?? null)) as Array<Record<string, unknown>> | null;
  if (rows === null) {
    return apiFail('server_error', 'operation_failed', 'The export could not be read. Try again in a moment.');
  }
  if (rows.length > RPE_LIMITS.csvMaxRows) {
    return apiFail('conflict', 'export_too_large', 'The export exceeds the 5,000-row limit. Narrow the date range and try again.');
  }

  if (dataset === 'payments') {
    const money = validatePaymentMoney(rows);
    if (!money.ok) return apiFail('server_error', 'export_integrity', money.error);
    // RPE-006 — the display column is the shared formatter's exact output over
    // the validated canonical paise; presentation only, never parsed back.
    for (const row of rows) {
      row.amount_display = formatMoney(String(row.amount_paise), typeof row.currency === 'string' ? row.currency : undefined);
    }
  }

  const now = new Date().toISOString();
  const exportId = crypto.randomUUID();
  const meta: ReportExportMeta = {
    exportId,
    generatedAtUtc: now,
    snapshotAtUtc: now,
    rangeFrom: from,
    rangeThrough: through,
    rangeBasis: REPORT_DATASETS[dataset].rangeBasis,
    timezone: !Array.isArray(payload) && typeof payload?.timezone === 'string' ? payload.timezone : DEFAULT_TIMEZONE,
    branchScope: branchId ?? 'whole_gym',
    dataRowCount: rows.length,
  };

  const auditDetails = (): Record<string, unknown> => ({
    tenant_id: session.tenantId,
    actor_user_id: session.userId,
    actor_role: session.role,
    dataset,
    range_from: from,
    range_through: through,
    range_basis: meta.rangeBasis,
    timezone: meta.timezone,
    branch_scope: meta.branchScope,
    row_count: rows.length,
  });

  const client = session.supabase as unknown as SnapshotClient;
  const prepared = await client.rpc('append_report_export_event', {
    p_event: 'report_export.prepared',
    p_export_id: exportId,
    p_details: auditDetails(),
  });
  if (prepared.error !== null) {
    return apiFail('server_error', 'audit_failed', 'The export could not be recorded in the audit log; nothing was released.');
  }

  const csv = buildReportCsv(dataset, meta, rows);
  const bytes = new TextEncoder().encode(csv);
  if (bytes.byteLength > RPE_LIMITS.csvMaxBytes) {
    return apiFail('conflict', 'export_too_large', 'The export exceeds the 8 MiB file limit. Narrow the date range and try again.');
  }
  // The deadline governs the whole prepare→release span, not just the read.
  if (Date.now() - startedAt > RPE_LIMITS.generationDeadlineMs) {
    return apiFail('server_error', 'export_timeout', 'The export took too long to generate. Narrow the date range and try again.');
  }

  const released = await client.rpc('append_report_export_event', {
    p_event: 'report_export.released',
    p_export_id: exportId,
    p_details: { ...auditDetails(), byte_count: bytes.byteLength, artifact_sha256: createHash('sha256').update(bytes).digest('hex') },
  });
  if (released.error !== null) {
    return apiFail('server_error', 'audit_failed', 'The export could not be recorded in the audit log; nothing was released.');
  }

  const filename = reportExportFilename(dataset, from, through, exportId);
  return new Response(csv, {
    headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': `attachment; filename="${filename}"`,
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    },
  });
}
