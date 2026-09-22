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

const mobileClientSchema = z.object({
  EXPO_PUBLIC_SUPABASE_URL: z.url(),
  EXPO_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1),
  EXPO_PUBLIC_API_BASE_URL: z.url(),
});

const playwrightSchema = z.object({
  DEMO_ACCOUNT_PASSWORD: z.string().min(1),
  PLAYWRIGHT_BASE_URL: z.url().default('http://127.0.0.1:3000'),
});

const pilotAcceptanceSchema = z.object({
  PILOT_SHARED_PROJECT_ACCEPTANCE: z.literal('ONE_SHARED_PRELAUNCH_PROJECT'),
});

/** A deploy-owned public origin used for OAuth redirects, never request input. */
const publicOriginSchema = z.url().refine((value) => {
  const url = new URL(value);
  return (url.protocol === 'http:' || url.protocol === 'https:') && url.origin === value;
}, 'Must be an origin without a path, query, or hash');

/** Server-only secrets. Never import serverEnv()/env() from client code. */
const serverOnlySchema = z.object({
  WEB_APP_URL: publicOriginSchema.default('http://127.0.0.1:3000'),
  SUPABASE_PROJECT_REF: z.string().min(1),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
  SUPABASE_DB_PASSWORD: z.string().min(1),
  CLOUDFLARE_ACCOUNT_ID: z.string().min(1),
  R2_ACCESS_KEY_ID: z.string().min(1),
  R2_SECRET_ACCESS_KEY: z.string().min(1),
  R2_BUCKET: z.string().min(1),
  R2_ENDPOINT: z.url(),
});

const webAppSchema = z.object({
  WEB_APP_URL: publicOriginSchema.default('http://127.0.0.1:3000'),
});

type ClientEnv = z.infer<typeof clientSchema>;
type ServerEnv = z.infer<typeof serverOnlySchema>;
type MobileClientEnv = z.infer<typeof mobileClientSchema>;
type PlaywrightEnv = z.infer<typeof playwrightSchema>;
type PilotAcceptanceEnv = z.infer<typeof pilotAcceptanceSchema>;

let cachedClient: ClientEnv | undefined;
let cachedServer: ServerEnv | undefined;
let cachedMobileClient: MobileClientEnv | undefined;

/**
 * Validated on first access, not at module load. An eager parse here would
 * throw during `next build` in CI (where no env vars are set), turning the
 * build gate red on missing secrets instead of on broken code — see
 * docs/decisions.md ADR-023.
 */
export function clientEnv(): ClientEnv {
  return (cachedClient ??= clientSchema.parse(process.env));
}

/** Expo-public values, referenced literally here so Metro can inline them. */
export function mobileClientEnv(): MobileClientEnv {
  return (cachedMobileClient ??= mobileClientSchema.parse({
    EXPO_PUBLIC_SUPABASE_URL: process.env.EXPO_PUBLIC_SUPABASE_URL,
    EXPO_PUBLIC_SUPABASE_ANON_KEY: process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY,
    EXPO_PUBLIC_API_BASE_URL: process.env.EXPO_PUBLIC_API_BASE_URL,
  }));
}

/** Browser-test credentials and endpoint, validated only when the harness starts. */
export function playwrightEnv(): PlaywrightEnv {
  return playwrightSchema.parse({
    DEMO_ACCOUNT_PASSWORD: process.env.DEMO_ACCOUNT_PASSWORD,
    PLAYWRIGHT_BASE_URL: process.env.PLAYWRIGHT_BASE_URL,
  });
}

/** Explicit, uncached opt-in for a manual shared-project pilot acceptance run. */
export function pilotAcceptanceEnv(): PilotAcceptanceEnv {
  return pilotAcceptanceSchema.parse({
    PILOT_SHARED_PROJECT_ACCEPTANCE: process.env.PILOT_SHARED_PROJECT_ACCEPTANCE,
  });
}

/** The deploy-owned public origin required by web OAuth, without server secrets. */
export function webAppEnv(): { WEB_APP_URL: string } {
  return webAppSchema.parse({ WEB_APP_URL: process.env.WEB_APP_URL });
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
