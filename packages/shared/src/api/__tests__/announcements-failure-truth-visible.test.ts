// Independent approved failure-truth contract; no implementation/holdouts read.
import { describe, expect, it } from 'vitest';
import { ANNOUNCEMENT_REFUSAL_COPY, announcementRefusalMessage } from '../announcements';

const unknownCopy = 'The result could not be confirmed. Reload to check whether the announcement was saved.';

describe('ANC approved unknown outcome copy', () => {
  it('adds the precise unknown outcome sentence without asserting no write', () => {
    expect(ANNOUNCEMENT_REFUSAL_COPY).toHaveProperty('unknown_outcome', unknownCopy);
    expect(announcementRefusalMessage('unknown_outcome')).toBe(unknownCopy);
    expect(unknownCopy).not.toContain('Nothing was changed');
  });
  it('preserves specific definitive and generic confirmed refusals', () => {
    expect(announcementRefusalMessage('not_draft')).toBe('This announcement is no longer a draft. Reload to see where it stands.');
    expect(announcementRefusalMessage('version_conflict')).toBe('Someone else changed this announcement while you were editing. Reload to see the latest version, then try again.');
    for (const reason of ['unknown', '__proto__', 'constructor']) {
      expect(announcementRefusalMessage(reason)).toBe('The announcement could not be saved. Nothing was changed.');
    }
  });
});
