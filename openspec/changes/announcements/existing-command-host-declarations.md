# Existing ANC command and caller host signatures

Declaration-only metadata, 2026-10-03. No behavior or interface changes.

```ts
// apps/web/lib/announcement-http.ts
type Command = 'create' | 'draft' | 'discard' | 'publish' | 'edit' |
  'unpublish' | 'feed' | 'read';
type Context = { params: Promise<{ announcementId: string }> };
declare function announcementCommand(
  request: Request, command: Command, context?: Context
): Promise<Response>;
// Existing registered apps/web/lib/api.ts auth host
type StaffSession = {
  supabase: SupabaseClient<Database>;
  userId: string; tenantId: string; staffId: string; role: StaffRole;
};
type MemberSession = {
  supabase: StaffSession['supabase'];
  userId: string; tenantId: string; memberId: string;
};
declare function staffSession(
  allowedRoles?: readonly StaffRole[],
  options?: { completeWrongAudience?: 'forbidden' }, request?: Request
): Promise<{ session: StaffSession } | { failure: Response }>;
declare function memberSession(
  request?: Request
): Promise<{ session: MemberSession } | { failure: Response }>;
```

These existing guards may be mocked as caller host seams, preserving supplied
request/role assertions. Actual shared parsing, command boundary and response
logic remain real. Authors may alternatively import actual registered POST
routes: `/api/announcements` for create; `/:announcementId/draft`, `/discard`,
`/publish`, `/edit`, `/unpublish`; member `/api/member/announcements/feed` and
`/:announcementId/read`. Id routes use the Context above. Every POST takes
the ordinary Request, with Context only for the id route. No browser-supplied
tenant/member field or alternative authority is introduced.
