import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { MS_PER_DAY, isoDaySchema, offsetInstantFromGymWallTime, toLocalDate, type PtReadSection } from '@gymloop/shared';
import type { BookingArgs, PackArgs, TrainerBooking, TrainerDay, TrainerPack, TrainerZone } from './trainer-view';

/**
 * TRV read coordinator (frozen public-declarations packet). One lease, one
 * date, one in-flight generation: a newer date/refresh/offline transition
 * supersedes the previous request, offline keeps only this lease's in-memory
 * day visibly marked last loaded, and a changed lease clears every fact.
 */

type ZoneResult = { data: TrainerZone | null; error: string | null };

function shiftDay(date: string | null, days: number): string | null {
  if (date === null || !isoDaySchema.safeParse(date).success) return null;
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * MS_PER_DAY).toISOString().split('T')[0]!;
}

export function useTrainerDay(options: {
  scopeKey: string | null;
  online: boolean;
  loadZone: () => Promise<ZoneResult>;
  loadBookings: (args: BookingArgs) => Promise<PtReadSection<TrainerBooking>>;
  loadPacks: (args: PackArgs) => Promise<PtReadSection<TrainerPack>>;
}): {
  day: TrainerDay | null;
  loading: boolean;
  stale: boolean;
  error: string | null;
  selectDate: (date: string) => void;
  today: () => void;
  previousDay: () => void;
  nextDay: () => void;
  refresh: () => void;
} {
  const { scopeKey, online, loadZone, loadBookings, loadPacks } = options;
  const [zone, setZone] = useState<TrainerZone | null>(null);
  const [zoneFailed, setZoneFailed] = useState(false);
  const [date, setDate] = useState<string | null>(null);
  const [day, setDay] = useState<TrainerDay | null>(null);
  const [loading, setLoading] = useState(false);
  const [stale, setStale] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const generation = useRef(0);
  const dayRef = useRef<TrainerDay | null>(null);
  dayRef.current = day;

  // A changed lease clears every loaded fact; nothing survives an identity switch.
  useEffect(() => {
    generation.current += 1;
    setZone(null);
    setZoneFailed(false);
    setDate(null);
    setDay(null);
    setLoading(false);
    setStale(false);
    setError(null);
  }, [scopeKey]);

  useEffect(() => {
    if (scopeKey === null || zone !== null || zoneFailed) return;
    let active = true;
    loadZone().then(result => {
      if (!active) return;
      if (result.error || result.data === null) {
        setZoneFailed(true);
        setDay(null);
        setLoading(false);
        setError("Couldn't load your sessions.");
      } else setZone(result.data);
    }).catch(() => {
      if (!active) return;
      setZoneFailed(true);
      setDay(null);
      setLoading(false);
      setError("Couldn't load your sessions.");
    });
    return () => { active = false; };
  }, [scopeKey, zone, zoneFailed, loadZone]);

  useEffect(() => {
    if (scopeKey === null || zone === null) return;
    const currentZone = zone;
    let effectiveDate = date;
    if (effectiveDate === null || !isoDaySchema.safeParse(effectiveDate).success) {
      effectiveDate = String(toLocalDate(new Date(), currentZone.timezone));
      setDate(effectiveDate);
    }
    if (!online) {
      // Offline: no new read; the same lease/date in-memory day stays, marked last loaded.
      generation.current += 1;
      setLoading(false);
      setStale(dayRef.current !== null);
      return;
    }
    const from = offsetInstantFromGymWallTime(`${effectiveDate}T00:00`, currentZone.timezone);
    const nextDay = shiftDay(effectiveDate, 1);
    const to = nextDay === null ? null : offsetInstantFromGymWallTime(`${nextDay}T00:00`, currentZone.timezone);
    if (from === null || to === null) {
      generation.current += 1;
      setLoading(false);
      setDay(null);
      setError("Couldn't load your sessions.");
      return;
    }
    const token = generation.current + 1;
    generation.current = token;
    setLoading(true);
    setStale(false);
    setError(null);
    void (async () => {
      const [bookings, packs] = await Promise.all([
        loadBookings({ p_from: from, p_to: to }),
        loadPacks({}),
      ]);
      if (generation.current !== token) return; // superseded by a newer request
      setDay({ date: effectiveDate, timezone: currentZone.timezone, bookings, packs });
      setLoading(false);
    })();
  }, [scopeKey, zone, date, online, tick, loadBookings, loadPacks]);

  const selectDate = useCallback((next: string) => {
    if (isoDaySchema.safeParse(next).success) setDate(next);
  }, []);
  const today = useCallback(() => {
    if (zone !== null) setDate(String(toLocalDate(new Date(), zone.timezone)));
  }, [zone]);
  const previousDay = useCallback(() => setDate(current => shiftDay(current, -1)), []);
  const nextDay = useCallback(() => setDate(current => shiftDay(current, 1)), []);
  const refresh = useCallback(() => setTick(value => value + 1), []);

  return useMemo(() => ({ day, loading, stale, error, selectDate, today, previousDay, nextDay, refresh }), [day, loading, stale, error, selectDate, today, previousDay, nextDay, refresh]);
}
