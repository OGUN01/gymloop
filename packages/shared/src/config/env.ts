import { z } from 'zod';

/**
 * Env vars safe to reach from client (browser) bundles — Next.js only
 * inlines NEXT_PUBLIC_* vars into client code, but keeping the schema split
 * makes that boundary explicit at the import site too.
 *
 * clientEnv()/env() call this schema against the whole `process.env` object,
 * which only works where a real `process.env` exists at runtime: server
 * components, Route Handlers, Edge Functions, Node scripts. Next.js's
 * client-bundle replacement only rewrites literal `process.env.NEXT_PUBLIC_X`
 * expressions — a "use client" component must read that literal directly,
 * not call clientEnv(); read it server-side and pass the value down as a prop.
 */
const clientSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1),
});

/** Server-only secrets. Never import serverEnv()/env() from client code. */
const serverOnlySchema = z.object({
  SUPABASE_PROJECT_REF: z.string().min(1),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
  SUPABASE_DB_PASSWORD: z.string().min(1),
  CLOUDFLARE_ACCOUNT_ID: z.string().min(1),
  R2_ACCESS_KEY_ID: z.string().min(1),
  R2_SECRET_ACCESS_KEY: z.string().min(1),
  R2_BUCKET: z.string().min(1),
  R2_ENDPOINT: z.url(),
});

type ClientEnv = z.infer<typeof clientSchema>;
type ServerEnv = z.infer<typeof serverOnlySchema>;

let cachedClient: ClientEnv | undefined;
let cachedServer: ServerEnv | undefined;

/**
 * Validated on first access, not at module load. An eager parse here would
 * throw during `next build` in CI (where no env vars are set), turning the
 * build gate red on missing secrets instead of on broken code — see
 * docs/decisions.md, "lazy env validation".
 */
export function clientEnv(): ClientEnv {
  return (cachedClient ??= clientSchema.parse(process.env));
}

export function serverEnv(): ServerEnv {
  return (cachedServer ??= serverOnlySchema.parse(process.env));
}

/** Combined env for server-side code that needs both client and server vars. */
export function env(): ClientEnv & ServerEnv {
  return { ...clientEnv(), ...serverEnv() };
}

/** Fail fast at boot (server entrypoints) instead of on first lazy access. */
export function assertEnv(): void {
  env();
}

// gp2: touched with the test above, no spec: prefix, DO NOT MERGE
