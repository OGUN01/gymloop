/**
 * The nightly no-show scan, triggered on a schedule.
 *
 * **This function holds no rule.** It authenticates the caller, calls one
 * database function, and reports what came back. Which members are at risk,
 * which gyms get scanned, what "absent" means and how a gym's day boundary is
 * decided all live in `app.run_no_show_scan` and
 * `public.run_no_show_scan_all` — where pgTAP can reach them, and where
 * `no_show_cases`' own grants and policies still apply.
 *
 * `docs/architecture.md` allows an Edge Function for exactly two things:
 * Razorpay webhooks and cron-triggered jobs. This is the second, and the reason
 * is that it must not depend on Vercel being up — a gym's red list is stale for
 * a day if this misses a night, and nothing else in the product notices.
 *
 * `Deno.env` rather than `serverEnv()`: AGENTS.md rule 3 names `process.env`,
 * which this runtime does not have, and `packages/shared` is platform-free by
 * construction (ADR-022) so it cannot hold a Deno accessor. The three names
 * read here are injected by the Edge Function runtime itself.
 *
 * KNOWN GAP, stated rather than discovered later: `supabase/functions/**` is
 * linted, registry-checked and dependency-cruised but **not typechecked**
 * (`docs/decisions.md`, "Known enforcement gaps"). Nothing here relies on
 * inference for correctness, and every response shape is asserted explicitly.
 */

const CRON_SECRET_HEADER = 'x-gymloop-cron-secret';

/**
 * Status codes as named constants, which is what AGENTS.md rule 4 asks for and
 * what `apps/web/app/api/members/member-input.ts` already does with `SEE_OTHER`.
 * They cannot come from `packages/shared/src/config/constants.ts`: this file is
 * Deno, that package is consumed through pnpm's workspace resolution, and
 * reaching across would be the platform leak ADR-022 exists to prevent.
 *
 * `no-magic-numbers` flags a literal used inline in an expression, which is
 * exactly what these were.
 */
const UNAUTHORISED = 401;
const MISCONFIGURED = 500;
const UPSTREAM_FAILED = 502;
const OK = 200;

type ScanRow = { tenant_id: string; gym: string; opened: number };

Deno.serve(async (request: Request): Promise<Response> => {
  // A scheduled job with a public URL is a public URL. Verified before anything
  // else happens and compared in full, because the only thing behind it is a
  // write to every gym's case list.
  const expected = Deno.env.get('CRON_SECRET');
  if (!expected) {
    // Refused rather than defaulted. A missing secret means the environment is
    // misconfigured, and running anyway would mean an unauthenticated endpoint
    // that opens cases — the failure mode is worse than not scanning tonight.
    return json({ ok: false, error: 'CRON_SECRET is not configured' }, MISCONFIGURED);
  }
  if (request.headers.get(CRON_SECRET_HEADER) !== expected) {
    return json({ ok: false, error: 'not authorised' }, UNAUTHORISED);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceRole) {
    return json({ ok: false, error: 'SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing' }, MISCONFIGURED);
  }

  // PostgREST directly rather than `supabase-js`: one RPC with no client to
  // pin, upgrade or audit. `service_role` is what the wrapper's execute grant
  // admits, and it is the one context in this product that legitimately spans
  // gyms — the per-gym function it calls still reads under row security.
  const response = await fetch(`${url}/rest/v1/rpc/run_no_show_scan_all`, {
    method: 'POST',
    headers: {
      apikey: serviceRole,
      Authorization: `Bearer ${serviceRole}`,
      'Content-Type': 'application/json',
    },
    body: '{}',
  });

  if (!response.ok) {
    const detail = await response.text();
    return json({ ok: false, error: 'scan failed', status: response.status, detail }, UPSTREAM_FAILED);
  }

  const rows: unknown = await response.json();
  if (!Array.isArray(rows)) {
    return json({ ok: false, error: 'scan returned an unexpected shape' }, UPSTREAM_FAILED);
  }

  const scanned = rows as ScanRow[];
  const opened = scanned.reduce((total, row) => total + (row.opened ?? 0), 0);

  // Per gym as well as the total. A total cannot tell "forty gyms, nothing to
  // do" from "one gym scanned and thirty-nine skipped", and those are the two
  // outcomes an operator most needs to tell apart at 6am.
  return json({ ok: true, gyms: scanned.length, opened, scanned });
});

function json(body: unknown, status = OK): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
