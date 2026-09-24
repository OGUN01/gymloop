import { PUBLIC_PAGE_PATHS } from '@gymloop/shared';
import { describe, expect, it } from 'vitest';
import { publicPageUrl } from '../public-page';
import { resolveRootDestination } from '../session';

const MEMBER = {
  kind: 'member' as const,
  userId: '11111111-1111-4111-8111-111111111111',
  tenantId: '22222222-2222-4222-8222-222222222222',
  memberId: '33333333-3333-4333-8333-333333333333',
};
const STAFF = {
  kind: 'staff' as const,
  userId: MEMBER.userId,
  tenantId: MEMBER.tenantId,
  staffId: '44444444-4444-4444-8444-444444444444',
  role: 'front_desk' as const,
};

describe('HARD-011 root destination for an unlinked session', () => {
  it('sends a provider-authenticated account with no complete identity to the not-linked screen', () => {
    expect(resolveRootDestination({ identity: { kind: 'unlinked' }, hasSession: true })).toBe('/not-linked');
  });

  it('still sends a missing session to sign-in', () => {
    expect(resolveRootDestination({ identity: { kind: 'unlinked' }, hasSession: false })).toBe('/sign-in');
  });

  it('keeps member, staff and platform homes unchanged', () => {
    expect(resolveRootDestination({ identity: MEMBER, hasSession: true })).toBe('/(member)');
    expect(resolveRootDestination({ identity: STAFF, hasSession: true })).toBe('/(desk)');
    expect(resolveRootDestination({ identity: { kind: 'platform', userId: MEMBER.userId, role: 'super_admin' }, hasSession: true })).toBe('platform');
  });
});

describe('Android public legal page URLs', () => {
  it('builds privacy and deletion URLs on the configured web origin', () => {
    expect(publicPageUrl('https://app.gymloop.example', PUBLIC_PAGE_PATHS.privacy)).toBe('https://app.gymloop.example/privacy');
    expect(publicPageUrl('https://app.gymloop.example/', PUBLIC_PAGE_PATHS.deleteAccount)).toBe('https://app.gymloop.example/delete-account');
    expect(publicPageUrl('https://app.gymloop.example', PUBLIC_PAGE_PATHS.deleteAccount)).toBe('https://app.gymloop.example/delete-account');
  });
});
