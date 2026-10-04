import { createPushDispatchHandler } from './handler.ts';

declare const Deno: { env: { get(name: string): string | undefined }; serve(handler: (request: Request) => Promise<Response>): void };

Deno.serve(createPushDispatchHandler({ readEnvironment: name => Deno.env.get(name), fetch: globalThis.fetch, now: Date.now, crypto: globalThis.crypto }));
