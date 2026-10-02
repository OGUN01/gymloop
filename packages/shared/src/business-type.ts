import { Constants } from '@gymloop/db';
import { z } from 'zod';
import type { StaffRole } from './api/identity';

export const BUSINESS_TYPES = Constants.public.Enums.business_type;
export type BusinessType = (typeof BUSINESS_TYPES)[number];
export const DEFAULT_BUSINESS_TYPE: BusinessType = 'gym';
export function isBusinessType(value: unknown): value is BusinessType {
  return typeof value === 'string' && (BUSINESS_TYPES as readonly string[]).includes(value);
}
export type BusinessNouns = { place: string; session: string; sessions: string; class: string; classes: string; member: string; members: string; trainer: string };
const NOUNS = {
  gym: { place: 'gym', session: 'session', sessions: 'sessions', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'trainer' },
  dance: { place: 'academy', session: 'class', sessions: 'classes', class: 'batch', classes: 'batches', member: 'student', members: 'students', trainer: 'instructor' },
  yoga: { place: 'studio', session: 'class', sessions: 'classes', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'teacher' },
  martial_arts: { place: 'academy', session: 'class', sessions: 'classes', class: 'class', classes: 'classes', member: 'student', members: 'students', trainer: 'instructor' },
  studio: { place: 'studio', session: 'session', sessions: 'sessions', class: 'class', classes: 'classes', member: 'member', members: 'members', trainer: 'trainer' },
} satisfies Record<BusinessType, BusinessNouns>;
export function businessNouns(type: BusinessType | null | undefined): BusinessNouns {
  return { ...NOUNS[isBusinessType(type) ? type : DEFAULT_BUSINESS_TYPE] };
}
export function businessRoleLabel(role: StaffRole, nouns: BusinessNouns): string {
  if (role === 'gym_owner') return `${nouns.place} owner`;
  if (role === 'gym_manager') return `${nouns.place} manager`;
  return role === 'trainer' ? nouns.trainer : 'front desk';
}
export const BUSINESS_TYPE_LABELS: Record<BusinessType, string> = { gym: 'Gym', dance: 'Dance academy', yoga: 'Yoga studio', martial_arts: 'Martial arts academy', studio: 'Fitness studio' };
export const BUSINESS_TYPE_SUMMARIES: Record<BusinessType, string> = {
  gym: 'Gyms and fitness centres.', dance: 'Dance academies and schools that run batches and classes.', yoga: 'Yoga studios that run classes.', martial_arts: 'Martial arts schools, dojos and boxing clubs.', studio: 'Pilates, cycling and other fitness studios.',
};
export const businessTypeCommandSchema = z.strictObject({ businessType: z.enum(BUSINESS_TYPES) });
export const setGymBusinessTypeRequestSchema = z.object({ expectedBusinessType: z.enum(BUSINESS_TYPES), businessType: z.enum(BUSINESS_TYPES), requestKey: z.uuid() }).strict();
export type BusinessTypeChange = { businessType: BusinessType; previousBusinessType: BusinessType; changed: boolean };
