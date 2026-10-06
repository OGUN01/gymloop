import * as Network from 'expo-network';
import { readMemberClasses, readMemberClassVisibility, readMemberUpcomingClassBookings, readClassTimetable, readClassRoster, classRefusalMessage, type ClassReadClient, type ClassReadWindow } from '@gymloop/shared';
import type { ApiClient, ApiEnvelope } from '@gymloop/api-client';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
export function loadMemberClasses(client: SupabaseClient<Database>, window: ClassReadWindow) { return readMemberClasses(client as unknown as ClassReadClient, window); }
export function loadMemberClassVisibility(client: SupabaseClient<Database>) { return readMemberClassVisibility(client as unknown as ClassReadClient); }
export function loadMemberUpcomingClassBookings(client: SupabaseClient<Database>) { return readMemberUpcomingClassBookings(client as unknown as ClassReadClient); }
export function loadDeskTimetable(client: SupabaseClient<Database>, window: ClassReadWindow & { branchId: string | null }) { return readClassTimetable(client as unknown as ClassReadClient, window); }
export function loadDeskRoster(client: SupabaseClient<Database>, sessionId: string) { return readClassRoster(client as unknown as ClassReadClient, sessionId); }
export function bookClass(api: ApiClient, sessionId: string, shouldSend?: () => boolean) { return onlineClassCommand<{ bookingId: string; status: Database['public']['Enums']['booking_status']; spotsLeft: number }>(api, '/api/class-bookings', { sessionId }, shouldSend); }
export function cancelClassBooking(api: ApiClient, bookingId: string, shouldSend?: () => boolean) { return onlineClassCommand<{ bookingId: string; status: Database['public']['Enums']['booking_status'] }>(api, '/api/class-bookings/cancel', { bookingId }, shouldSend); }
export function deskBookClass(api: ApiClient, sessionId: string, memberId: string, shouldSend?: () => boolean) { return onlineClassCommand<{ bookingId: string; status: Database['public']['Enums']['booking_status']; spotsLeft: number }>(api, '/api/class-bookings/desk', { sessionId, memberId }, shouldSend); }
export function deskCancelClassBooking(api: ApiClient, bookingId: string, reason: string, shouldSend?: () => boolean) { return onlineClassCommand<{ bookingId: string; status: Database['public']['Enums']['booking_status'] }>(api, '/api/class-bookings/desk-cancel', { bookingId, reason }, shouldSend); }
export function markClassAttendance(api: ApiClient, bookingId: string, status: Database['public']['Enums']['booking_status'], shouldSend?: () => boolean) { return onlineClassCommand<{ bookingId: string; status: Database['public']['Enums']['booking_status'] }>(api, '/api/class-bookings/attendance', { bookingId, status }, shouldSend); }

/** Online-only explicit commands: unknown connectivity refuses without retaining a replay. */
async function onlineClassCommand<T>(api: ApiClient, path: string, body: unknown, shouldSend?: () => boolean): Promise<ApiEnvelope<T>> {
  const refused: ApiEnvelope<T> = { ok: false, error: { code: 'booking_failed', message: classRefusalMessage('booking_failed') } };
  if (!classCommandCurrent(shouldSend)) return refused;
  try {
    const state = await Network.getNetworkStateAsync();
    if (state.isConnected !== true || state.isInternetReachable !== true) return { ok: false, error: { code: 'offline', message: classRefusalMessage('offline') } };
  } catch { return { ok: false, error: { code: 'offline', message: classRefusalMessage('offline') } }; }
  if (!classCommandCurrent(shouldSend)) return refused;
  return api.post<T>(path, body);
}

function classCommandCurrent(shouldSend?: () => boolean): boolean {
  try { return shouldSend === undefined || shouldSend(); } catch { return false; }
}
