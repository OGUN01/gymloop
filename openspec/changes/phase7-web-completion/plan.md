# Phase 7 web route completion

## Frozen scope

Apply UX7-003–007/012–014 and ADR-128/130 to the remaining existing web route
interiors without changing their loaders, actions, authorization, money or
response contracts. The literal references are the approved member and owner
v2 boards. This slice owns only presentation in:

- owner: `members`, `memberships`, `payments`, `messages`, `add-ons`, `leads`,
  `imports` and their existing detail routes;
- member: `/member/messages` and `/member/add-ons` plus the member shell;
- platform: `/platform` and `/platform/[id]` with function-first priority;
- shared private CSS for those route hooks in `apps/web/app/globals.css`.

Every route uses the shared tokens, compact continuous geometry, restrained
depth, truthful empty/error/loading/refusal states and complete Light/Dark.
Owner desktop uses the existing rail and compact 52–56px rows; 1024 and 390px
reflow without page overflow. Member routes foreground verified gym/member
context and at least 48px touch controls. Platform keeps support preview
read-only and uses the same typography/forms without inventing dashboard data.

No dependency, API, `apps/web/lib`, SQL, identity, domain mutation, schema,
generated type or test may be changed by the implementer. Existing forms,
names, methods, hidden CAS/idempotency fields, actions and links remain exact.
No decorative placeholder or disabled future control may represent an
unimplemented member Home/Activity/My gym/You flow.

## Ownership and acceptance

An independent Luna author adds one focused presentation contract under
`apps/web/app/__tests__/phase7-web-completion.test.tsx` before implementation.
A separate Luna implementer receives exact route groups and may change only the
listed route components/member frame/private CSS. Root owns registry/spec/
evidence/archive. Focused tests plus web typecheck/lint close development; real
owner/member/platform Light/Dark journeys at 1600/1024/390 and a fresh Sol crop
comparison close the slice.

- [x] Contract frozen before dispatch.
- [ ] Independent route test committed red.
- [ ] Remaining web interiors implemented.
- [ ] Focused checks and browser journeys green.
- [ ] Fresh Sol critic GO; spec/evidence synchronized and archived.
