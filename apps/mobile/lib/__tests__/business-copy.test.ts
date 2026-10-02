import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const surfaces = {
  'app/(member)/index.tsx': ['Your gym information is unavailable.', 'Opens the camera to scan your gym QR code', 'Camera access is needed only while you scan the gym QR.', 'Latest from your gym'],
  'app/(member)/activity.tsx': ['Gym QR', 'Your visits appear here once the gym confirms a check-in.'],
  'app/(member)/gym.tsx': ['My gym', 'Gym details are unavailable.', 'Gym code', 'Opens the member check-in scanner'],
  'app/(member)/you.tsx': ['Verified member', 'Member account'],
  'components/role-tabs.tsx': ['My gym'],
  'components/ui.tsx': ['Loading your gym'],
  'lib/use-member-snapshot.ts': ['Your gym information could not be loaded.'],
  'app/(desk)/index.tsx': ['For members who can’t scan.', 'Search members', 'Members could not be loaded.', 'No matching members'],
  'app/(desk)/members.tsx': ['Search members', 'Members could not be loaded.', 'No matching members'],
  'app/(desk)/follow-ups.tsx': ['Everyone on the list has been contacted or is back in the gym.', 'No matching members'],
};

describe('BIZ-012 mobile copy consumers', () => {
  it.each(Object.entries(surfaces))('%s takes current-tenant nouns', (path, legacy) => {
    const source = readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
    expect(source).toMatch(/import[\s\S]*?\buseBusinessNouns\b[\s\S]*?from\s*['"]/);
    expect(source).toMatch(/\buseBusinessNouns\s*\(/);
    for (const literal of legacy) expect(source, literal).not.toContain(literal);
  });
  it('keeps the stored desk-assist reason literal', () => {
    const source = readFileSync(new URL('../../app/(desk)/index.tsx', import.meta.url), 'utf8');
    expect(source).toContain('Member requested desk assistance');
  });
});
