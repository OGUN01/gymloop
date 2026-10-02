import { describe, expect, it } from 'vitest';
import { Constants } from '@gymloop/db';
import { humanize } from '../display/display';
import { BUSINESS_TYPES, BUSINESS_TYPE_LABELS, BUSINESS_TYPE_SUMMARIES, DEFAULT_BUSINESS_TYPE,
  businessNouns, businessRoleLabel, businessTypeCommandSchema, isBusinessType, setGymBusinessTypeRequestSchema } from '../business-type';

const golden = {
  gym: { place: 'gym', session: 'session', sessions: 'sessions', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'trainer' },
  dance: { place: 'academy', session: 'class', sessions: 'classes', class: 'batch', classes: 'batches', member: 'student', members: 'students', trainer: 'instructor' },
  yoga: { place: 'studio', session: 'class', sessions: 'classes', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'teacher' },
  martial_arts: { place: 'academy', session: 'class', sessions: 'classes', class: 'class', classes: 'classes', member: 'student', members: 'students', trainer: 'instructor' },
  studio: { place: 'studio', session: 'session', sessions: 'sessions', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'trainer' },
} as const;

describe('BIZ-009 canonical business vocabulary', () => {
  it('uses the generated enum in its exact contract order', () => {
    expect(BUSINESS_TYPES).toEqual(Constants.public.Enums.business_type);
    expect(BUSINESS_TYPES).toEqual(['gym', 'dance', 'yoga', 'martial_arts', 'studio']);
    expect(DEFAULT_BUSINESS_TYPE).toBe('gym');
  });
  it.each(Object.keys(golden) as Array<keyof typeof golden>)('%s has exactly the eight golden nouns and correct role labels', (type) => {
    const nouns = businessNouns(type);
    expect(nouns).toEqual(golden[type]);
    expect(isBusinessType(type)).toBe(true);
    expect(businessRoleLabel('gym_owner', nouns)).toBe(`${nouns.place} owner`);
    expect(businessRoleLabel('gym_manager', nouns)).toBe(`${nouns.place} manager`);
    expect(businessRoleLabel('front_desk', nouns)).toBe('front desk');
    expect(businessRoleLabel('trainer', nouns)).toBe(nouns.trainer);
    for (const noun of Object.values(nouns)) {
      const initial = noun[0];
      if (initial === undefined) throw new Error('Every golden business noun must have an initial letter');
      expect(humanize(noun)).toBe(initial.toUpperCase() + noun.slice(1));
    }
  });
  it.each([null, undefined, '', 'custom', 'GYM', {}, 1])('falls back safely for invalid value %j', (value) => {
    expect(businessNouns(value as never)).toEqual(golden.gym);
    expect(isBusinessType(value)).toBe(false);
  });
  it('cannot corrupt later callers through a returned vocabulary object', () => {
    const nouns = businessNouns('dance');
    try { Object.assign(nouns, { place: 'corrupted' }); } catch { /* frozen objects may reject mutation */ }
    expect(businessNouns('dance')).toEqual(golden.dance);
  });
  it('labels and summaries are exact and total', () => {
    expect(BUSINESS_TYPE_LABELS).toEqual({ gym: 'Gym', dance: 'Dance academy', yoga: 'Yoga studio', martial_arts: 'Martial arts academy', studio: 'Fitness studio' });
    expect(BUSINESS_TYPE_SUMMARIES).toEqual({ gym: 'Gyms and fitness centres.', dance: 'Dance academies and schools that run batches and classes.', yoga: 'Yoga studios that run classes.', martial_arts: 'Martial arts schools, dojos and boxing clubs.', studio: 'Pilates, cycling and other fitness studios.' });
  });
  it('accepts only a listed type and rejects spoofed tenant/actor fields', () => {
    expect(businessTypeCommandSchema.safeParse({ businessType: 'dance' }).success).toBe(true);
    for (const value of [{}, { businessType: 'custom' }, { businessType: null }, { businessType: 'gym', tenantId: 'other' }, { businessType: 'gym', actor: 'owner' }]) {
      expect(businessTypeCommandSchema.safeParse(value).success).toBe(false);
    }
  });
  it('platform schema requires both canonical types and a UUID request key, with no additional fields', () => {
    const valid = { expectedBusinessType: 'gym', businessType: 'yoga', requestKey: '70000000-0000-4000-8000-000000000401' };
    expect(setGymBusinessTypeRequestSchema.safeParse(valid).success).toBe(true);
    for (const value of [{ ...valid, requestKey: 'bad' }, { ...valid, expectedBusinessType: 'custom' }, { ...valid, businessType: 'custom' }, { ...valid, tenantId: 'injected' }]) {
      expect(setGymBusinessTypeRequestSchema.safeParse(value).success).toBe(false);
    }
  });
});
