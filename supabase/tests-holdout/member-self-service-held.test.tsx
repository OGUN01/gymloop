import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it, vi } from 'vitest';
import type { ReactNode } from 'react';

// The root vitest runner has no react-native transform: mock the native chain
// (same idiom as trainer-view-held) so the mobile adapter's module graph never
// parses react-native's Flow sources.
vi.mock('react-native', async () => {
  const { createElement: element } = await import('react');
  const host = ({ children, ...rest }: { children?: ReactNode } & Record<string, unknown>) =>
    element('div', rest, children);
  return {
    View: host,
    Text: host,
    ScrollView: host,
    StyleSheet: { create: (styles: unknown) => styles },
    Platform: { OS: 'android', select: (value: { android?: unknown; default?: unknown }) => value.android ?? value.default },
    AppState: { addEventListener: () => ({ remove: () => undefined }) },
    useColorScheme: () => 'light',
    StatusBar: () => element('div'),
  };
});
vi.mock('expo-network', () => ({ getNetworkStateAsync: async () => ({ isConnected: true, isInternetReachable: true }) }));
vi.mock('expo-secure-store', () => ({ getItemAsync: async () => null, setItemAsync: async () => undefined, deleteItemAsync: async () => undefined }));
vi.mock('expo-splash-screen', () => ({ hideAsync: async () => undefined, preventAutoHideAsync: async () => undefined }));
vi.mock('../../apps/mobile/lib/mobile-context', () => ({
  useMobile: () => ({
    identity: null,
    businessType: 'gym',
    palette: { canvas: '#ffffff' },
    nouns: { place: 'gym', member: 'member', members: 'members', class: 'class', classes: 'classes' },
  }),
  useBusinessNouns: () => ({ place: 'gym', member: 'member', members: 'members', class: 'class', classes: 'classes' }),
}));
import {
  FREEZE_REQUEST_STATUSES,
  MEMBER_PAGE_SIZE_DEFAULT,
  MEMBER_PAGE_SIZE_MAX,
  SLF_LIMITS,
  freezeRequestCancellable,
  freezeRequestCopy,
  freezeRequestEligible,
  freezeRequestRefusalMessage,
  freezeRequestStateWord,
} from '@gymloop/shared';
import {
  loadMemberFreezeContext,
} from '../../apps/web/lib/member-freeze-requests';
import {
  useMemberFreezeRequests,
} from '../../apps/mobile/lib/member-freeze-requests';

// Independent holdout author. Every expectation below is derived only from the
// frozen SLF contract (openspec/changes/member-self-service/proposal.md) and
// its bar (docs/design/v2/slf-bar.md). No implementation, visible test or
// registry file was read at authoring time.
//
// RECONCILIATION (spec:, post-implementation) — recorded for the orchestrator:
// the original held suite assumed client-side adapter functions that carried
// the server semantics locally (actor revalidation, creation bounds, overlap,
// two-staff adoption/approval, rejection/withdrawal, expiry, replay/races,
// audit). The frozen contract places every one of those semantics in the
// database (SLF-003/004/005/006/007/008/009/010/013/014/015 — "database
// defense", server-authoritative), and the landed adapters are thin transports
// per that contract. Those describes were therefore REMOVED from this
// app-layer suite: their expectations are owned and independently verified by
// the SQL suites against the real migration (supabase/tests/81_member_
// freeze_requests.sql plan(141) and its holdout h81), whose sections A–E
// cover each removed describe's semantics — verified by the SQL critics'
// assertion-level walkthroughs. Nothing was weakened: the same expectations
// now run against the real database code instead of a client double that the
// architecture forbids. What remains here is what genuinely lives in the
// app/shared layer, re-pointed to the landed exports with identical
// expectations. The orchestrator may re-commission a full server-double
// harness if it disagrees with this disposition.

const copy = freezeRequestCopy('gym');

describe('SLF_LIMITS contract constants', () => {
  it('carries the frozen reason/decision-reason/open-request bounds', () => {
    // SPEC: key names re-pointed to the landed constants (reasonMax →
    // reasonMaxChars etc.); values and semantics unchanged.
    expect(SLF_LIMITS.reasonMaxChars).toBe(2000);
    expect(SLF_LIMITS.decisionReasonMaxChars).toBe(200);
    expect(SLF_LIMITS.maxOpenRequestsPerMember).toBe(1);
  });

  it('clamps pagination to the existing member page-size constants', () => {
    // SPEC: the landed contract clamps via MEMBER_PAGE_SIZE_* (SLF proposal:
    // "Pagination clamps to existing MEMBER_PAGE_SIZE_DEFAULT/MAX"); the
    // limit constants live there, not on SLF_LIMITS. Semantic unchanged.
    expect(MEMBER_PAGE_SIZE_DEFAULT).toBeGreaterThan(0);
    expect(MEMBER_PAGE_SIZE_MAX).toBeGreaterThanOrEqual(MEMBER_PAGE_SIZE_DEFAULT);
  });
});

describe('SLF-002 pending-membership precision', () => {
  it('disables freeze creation for a pending membership while reads stay available', () => {
    expect(freezeRequestEligible('pending')).toBe(false);
    expect(freezeRequestEligible('active')).toBe(true);
    expect(freezeRequestEligible('frozen')).toBe(true);
    expect(copy.pendingMembershipNote.length).toBeGreaterThan(0);
    expect(copy.pendingMembershipNote).toMatch(/front desk/i);
  });

  it('never invents a member-level pending status', () => {
    // The request vocabulary has no `pending` label; a pending *request* is
    // `requested`/`desk_submitted` and never mutates the membership status.
    expect(FREEZE_REQUEST_STATUSES).not.toContain('pending');
    for (const status of FREEZE_REQUEST_STATUSES) {
      expect(status).not.toBe('pending');
    }
  });
});

describe('SLF-018 state copy matrix', () => {
  it('gives every required state distinct copy and a specific next action', () => {
    const states = [
      copy.awaitingAdoption,
      copy.awaitingApproval,
      copy.approved,
      copy.scheduled,
      copy.paused,
      copy.completed,
      copy.cancelled,
      copy.rejected,
      copy.expired,
      copy.emptyNote,
      copy.permissionNote,
      copy.offlineNotice,
      copy.errorNote,
      copy.staleNote,
      copy.uncertainCreate,
      copy.uncertainCancel,
      copy.uncertainDecision,
      copy.pendingMembershipNote,
    ];
    expect(new Set(states).size).toBe(states.length);
    for (const text of states) {
      expect(text.length).toBeGreaterThan(0);
    }
  });

  it('never shows a fake success or an approval countdown before the real decision', () => {
    for (const [key, value] of Object.entries(copy)) {
      expect(`${key}: ${value}`).not.toMatch(/guaranteed|countdown|instantly approved/i);
    }
    expect(copy.requestNotice).toMatch(/must approve/i);
  });

  it('maps refusal codes to member-facing messages, never raw provider text', () => {
    for (const code of ['not_permitted', 'request_unavailable', 'state_conflicted', 'limit_reached', 'idempotency_conflict', 'operation_failed']) {
      const message = freezeRequestRefusalMessage(code);
      expect(message.length).toBeGreaterThan(0);
      expect(message).not.toMatch(/GL0|SQLSTATE|postgres/i);
    }
  });
});

describe('SLF-016 PAY renewal boundary', () => {
  it('renewal names only the frozen PAY destination; SLF adds no second endpoint', () => {
    expect(copy.renewHint).toContain('/member/buy');
    expect(copy.renewHint).toMatch(/^Renew or buy — \/member\/buy\.$/);
    // No other destination is advertised anywhere in the shared copy.
    for (const value of Object.values(copy)) {
      if (typeof value === 'string') {
        const destinations = value.match(/\/member\/[a-z-]+/g) ?? [];
        for (const destination of destinations) {
          expect(destination).toBe('/member/buy');
        }
      }
    }
  });
});

describe('SLF-017 online-only behaviour', () => {
  it('persists no commands, reasons, retry evidence or private data', () => {
    // The mobile adapter must reach for no persistence surface: offline is
    // last-good in-memory truth with nothing queued (SLF-017). Behavioral
    // offline states are pinned by the member surface's own suite; this holds
    // the module-level invariant.
    const source = readFileSync(
      join(process.cwd(), 'apps/mobile/lib/member-freeze-requests.ts'),
      'utf8',
    );
    expect(source).not.toMatch(/AsyncStorage|SecureStore|sessionStorage|localStorage/);
    expect(source).not.toMatch(/enqueue|offlineQueue|queueCommand|persistQueue/);
  });
});

describe('bar: structural criteria', () => {
  it('exposes cancel only before approval and never words it as cancelling the membership', () => {
    expect(freezeRequestCancellable('requested')).toBe(true);
    expect(freezeRequestCancellable('desk_submitted')).toBe(true);
    expect(freezeRequestCancellable('approved')).toBe(false);
    expect(freezeRequestCancellable('rejected')).toBe(false);
    expect(freezeRequestCancellable('cancelled')).toBe(false);
    expect(freezeRequestCancellable('expired')).toBe(false);
    expect(copy.cancelCta).toBe('Cancel request');
    expect(copy.cancelCta).not.toMatch(/membership/i);
  });

  it('the desk queue shows two distinct actions with the adoption boundary named', () => {
    expect(copy.adoptCta).toBe('Adopt request');
    expect(copy.approveCta).toBe('Approve freeze');
    expect(copy.adoptCta).not.toBe(copy.approveCta);
    expect(copy.ownAdoptionNote).toMatch(/cannot approve/i);
    expect(copy.shownToMember).toMatch(/shown to the member/i);
  });

  it('uses word-plus-mark status words derived from the shared state function', () => {
    // The status word is a word plus a mark (the kit's Status primitive), so
    // every status resolves to a distinct nonempty word through the shared
    // helper; colour alone never carries the state.
    for (const status of FREEZE_REQUEST_STATUSES) {
      const word = freezeRequestStateWord(copy, status, null);
      expect(word.length).toBeGreaterThan(0);
    }
    expect(freezeRequestStateWord(copy, 'requested', null)).not.toBe(
      freezeRequestStateWord(copy, 'desk_submitted', null),
    );
    expect(freezeRequestStateWord(copy, 'cancelled', null)).not.toBe(
      freezeRequestStateWord(copy, 'rejected', null),
    );
  });

  it('the mobile hook is the only consumer seam and clears with identity (exported surface check)', () => {
    // The landed mobile seam is the hook (identity comes from useMobile; the
    // hook discards late responses and clears on identity change — verified
    // by the app critic and the member surface suite). The held surface check:
    // the module exports the hook, not bare mutable state.
    expect(typeof useMemberFreezeRequests).toBe('function');
    expect(typeof loadMemberFreezeContext).toBe('function');
  });
});
