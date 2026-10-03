import { useCallback, useEffect, useRef, useState } from 'react';
import { useRouter } from 'expo-router';
import { useMobile } from './mobile-context';
import { notificationsModule } from './use-member-push';

/**
 * The client half of push receipt and safe opens (NTF-009/010). The OS
 * listeners are registered on mount: a push presented while the app is
 * foreground reports `received`, a member's tap on a push reports `opened`,
 * and both travel through the member push-event route — never fabricated from
 * provider acceptance or list rendering. An open routes through the frozen
 * allowlist only (member inbox, membership, class detail, live ANC card); the
 * push-event command itself is the revalidation — a successful response means
 * the source is currently exposed to this identity, and any refusal shows
 * "That update isn't available." instead of a route.
 *
 * A tap that arrives while signed out waits: the open stays queued until the
 * session is a ready member again, then revalidates. A queued item is dropped
 * when the account changes; offline items retry when the hook next runs.
 */
type PushPayload = { notificationId?: unknown; sourceNotificationId?: unknown; relatedType?: unknown; relatedId?: unknown };

/** The frozen open allowlist: tab-level destinations only, never payload URLs. */
const ROUTE_BY_TYPE: Record<string, string> = {
  announcement: '/(member)',
  inbox: '/(member)/activity',
  membership: '/(member)/gym',
  class_session: '/(member)/classes',
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (value: unknown): value is string => typeof value === 'string' && UUID.test(value);

type QueuedOpen = { notificationId: string; event: 'received' | 'opened'; relatedType: string | null };

type PushResponse = { notification?: { request?: { content?: { data?: unknown } } } };

/** Resolves an OS payload to a queued open: unknown shapes are discarded, not guessed. */
function parsePushOpen(data: unknown): { notificationId: string; relatedType: string | null } | null {
  if (data === null || typeof data !== 'object') return null;
  const value = data as PushPayload;
  if (!isUuid(value.notificationId)) return null;
  const relatedType = typeof value.relatedType === 'string' && Object.hasOwn(ROUTE_BY_TYPE, value.relatedType) ? value.relatedType : null;
  return { notificationId: value.notificationId, relatedType };
}

export function useMemberPushResponse(registration: { deviceId: string; tokenRevision: number } | null) {
  const { api, ready, identity } = useMobile() as { api: { post: (path: string, body: unknown) => Promise<{ ok: boolean }> }; ready: boolean; identity: { kind: string; memberId?: string } };
  const router = useRouter();
  const [unavailable, setUnavailable] = useState(false);
  const queueRef = useRef<QueuedOpen[]>([]);
  const postedRef = useRef<Set<string>>(new Set());
  const authRef = useRef({ ready, isMember: identity.kind === 'member' });
  authRef.current = { ready, isMember: identity.kind === 'member' };
  const memberIdRef = useRef<string | null>(identity.kind === 'member' ? identity.memberId : null);
  const registrationRef = useRef(registration);
  registrationRef.current = registration;
  const routerRef = useRef(router);
  routerRef.current = router;

  const process = useCallback(async () => {
    if (!authRef.current.ready || !authRef.current.isMember) return;
    const registration = registrationRef.current;
    const pending = queueRef.current;
    queueRef.current = [];
    for (const item of pending) {
      // No registered device means no accepted attempt can exist for this
      // install: a receipt has no channel. Keep nothing, claim nothing.
      if (registration === null) continue;
      const key = `${item.notificationId}:${item.event}`;
      if (postedRef.current.has(key)) continue;
      postedRef.current.add(key);
      try {
        const reply = await api.post(`/api/member/notifications/${item.notificationId}/push-event`, {
          deviceId: registration.deviceId,
          tokenRevision: registration.tokenRevision,
          event: item.event,
        });
        if (reply.ok) {
          const route = item.relatedType === null ? null : ROUTE_BY_TYPE[item.relatedType];
          // The map's values are the allowlisted typed routes; the cast only
          // names what the allowlist already guarantees.
          if (item.event === 'opened' && route !== undefined) routerRef.current.push(route as Parameters<typeof routerRef.current.push>[0]);
        } else {
          setUnavailable(true);
        }
      } catch {
        // Offline or lost response: the evidence stays queued for a retry and
        // nothing claims a receipt it has not recorded yet.
        if (!postedRef.current.has(`${item.notificationId}:${item.event}`)) continue;
        postedRef.current.delete(key);
        queueRef.current.push(item);
      }
    }
  }, [api]);

  const handle = useCallback((data: unknown, event: 'received' | 'opened') => {
    const parsed = parsePushOpen(data);
    if (parsed === null) return; // Unknown/malformed payload data is discarded.
    const memberId = identity.kind === 'member' ? identity.memberId : null;
    if (memberId !== memberIdRef.current) {
      // Account change discards everything waiting to be reported or opened.
      memberIdRef.current = memberId;
      queueRef.current = [];
      postedRef.current = new Set();
    }
    queueRef.current.push({ notificationId: parsed.notificationId, event, relatedType: parsed.relatedType });
    void process();
  }, [identity, process]);

  // Wait-then-revalidate: items queued while signed out process when a ready
  // member session exists again.
  useEffect(() => {
    void process();
  }, [ready, identity, process]);

  useEffect(() => {
    let live = true;
    const removes: Array<() => void> = [];
    void notificationsModule().then((module) => {
      if (!live || module === null) return;
      // A cold-start tap is kept by the OS; handle it once before listeners.
      if (typeof module.getLastNotificationResponseAsync === 'function') {
        void module.getLastNotificationResponseAsync()
          .then((response) => {
            const data = (response as PushResponse | null)?.notification?.request?.content?.data;
            if (data !== undefined) handle(data, 'opened');
          })
          .catch(() => undefined);
      }
      if (typeof module.addNotificationReceivedListener === 'function') {
        const sub = module.addNotificationReceivedListener((notification) => {
          const data = (notification as { request?: { content?: { data?: unknown } } } | undefined)?.request?.content?.data;
          if (data !== undefined) handle(data, 'received');
        });
        removes.push(() => sub.remove());
      }
      if (typeof module.addNotificationResponseReceivedListener === 'function') {
        const sub = module.addNotificationResponseReceivedListener((response) => {
          const data = (response as PushResponse | undefined)?.notification?.request?.content?.data;
          if (data !== undefined) handle(data, 'opened');
        });
        removes.push(() => sub.remove());
      }
    }).catch(() => undefined);
    return () => { live = false; removes.forEach((remove) => remove()); };
  }, [handle]);

  return { unavailable };
}

