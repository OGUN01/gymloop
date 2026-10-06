/** App-run continuity for one exact, confirmed member identity. */
export const memberClassVisibilityCache: { scope: string | null; enabled: boolean | null; revision: object } = { scope: null, enabled: null, revision: {} };

/** Revoke pending reads before identity cleanup waits on any other feature. */
export function clearMemberClassVisibilityCache(): Promise<void> {
  memberClassVisibilityCache.revision = {};
  memberClassVisibilityCache.scope = null;
  memberClassVisibilityCache.enabled = null;
  return Promise.resolve();
}
