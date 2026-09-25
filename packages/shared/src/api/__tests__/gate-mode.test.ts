import { describe, expect, it } from 'vitest';
import { gateModeCommandSchema } from '../gate-mode';

describe('check-in gate command contract', () => {
  it('accepts only the two canonical modes with no caller-supplied tenant or staff id', () => {
    expect(gateModeCommandSchema.parse({ mode: 'printed_poster' })).toEqual({ mode: 'printed_poster' });
    expect(gateModeCommandSchema.parse({ mode: 'rotating_screen' })).toEqual({ mode: 'rotating_screen' });
    expect(gateModeCommandSchema.safeParse({ mode: 'printed_poster', tenantId: 'foreign' }).success).toBe(false);
    expect(gateModeCommandSchema.safeParse({ mode: 'poster' }).success).toBe(false);
  });
});
