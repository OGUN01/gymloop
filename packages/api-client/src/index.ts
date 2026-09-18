import { checkInRequestSchema, type CheckInRequest } from '@gymloop/shared';
import { z } from 'zod';

const apiErrorSchema = z.object({ code: z.string(), message: z.string() }).passthrough();
const errorEnvelopeSchema = z.object({ ok: z.literal(false), error: apiErrorSchema });
const successEnvelopeSchema = z.object({ ok: z.literal(true), data: z.unknown() });

export const apiEnvelopeSchema = z.union([successEnvelopeSchema, errorEnvelopeSchema]);
export type ApiError = z.infer<typeof apiErrorSchema>;
export type ApiEnvelope<T = unknown> = { ok: true; data: T } | { ok: false; error: ApiError };
export type CheckInResult = { id: string; checked_in_at: string; source: string; memberName: string; replay: boolean };

export type ApiFetch = (
  input: string,
  init: { method: 'POST'; headers: Readonly<Record<string, string>>; body: string },
) => Promise<{ json(): Promise<unknown> }>;
export type ApiClientOptions = { baseUrl: string; accessToken: () => Promise<string | null>; fetch: ApiFetch };
export type ApiClient = {
  checkIn(command: CheckInRequest): Promise<ApiEnvelope<CheckInResult>>;
  post<T = unknown>(path: string, body: unknown): Promise<ApiEnvelope<T>>;
};

function endpoint(baseUrl: string, path: string): string {
  return `${baseUrl.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;
}

/** Platform-neutral envelope client with injected network and bearer providers. */
export function createApiClient(options: ApiClientOptions): ApiClient {
  const post = async <T>(path: string, body: unknown): Promise<ApiEnvelope<T>> => {
    const token = await options.accessToken();
    const response = await options.fetch(endpoint(options.baseUrl, path), {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...(token === null ? {} : { authorization: `Bearer ${token}` }) },
      body: JSON.stringify(body),
    });
    return apiEnvelopeSchema.parse(await response.json()) as ApiEnvelope<T>;
  };
  return { post, checkIn: async (command) => await post<CheckInResult>('/api/check-in', checkInRequestSchema.parse(command)) };
}
