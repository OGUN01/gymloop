'use client';

import { businessNouns, type BusinessNouns, UI_TOKENS } from '@gymloop/shared';
import { Bell, BellOff } from 'lucide-react';

/**
 * The member web Notifications section (NTF-016). Categories render with
 * their exact system names so support can match a member's settings, and the
 * truthful provider state shows through: web push is not available in this
 * browser and, while the gym's push provider is unconfigured, every surface
 * says so instead of promising delivery (pre-configuration amendment). The
 * defaults shown are the missing-row defaults — a missing preference row
 * means push is enabled subject to consent and OS permission.
 */
const PUSH_CATEGORIES = [
  'renewal', 'payment', 'fulfilment', 'promotion', 'motivation', 'class_update', 'announcement',
] as const;

const smallIcon = { 'aria-hidden': true, size: UI_TOKENS.icons.controlSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;

// The two contract sentences are static, reviewable constants (no caller input
// reaches them), rendered as raw HTML so the literal copy — apostrophe
// included — reaches both the reader and the copy-verified markup unescaped.
const WEB_PUSH_UNAVAILABLE = "Web push isn't available on this browser — use the FitCruxx mobile app for device notifications.";
const PUSH_UNCONFIGURED = "Push isn't configured. Updates remain in the app.";

export function YouNotifications({ nouns = businessNouns(null) }: { nouns?: BusinessNouns }) {
  return (
    <section className="member-push" aria-label="Notifications">
      <h3 className="member-push-heading"><Bell {...smallIcon} />Notifications</h3>
      <ul className="member-push-categories" aria-label="Push categories">
        {PUSH_CATEGORIES.map((category) => (
          <li key={category} className="member-push-category" aria-label={`Push category ${category}, enabled by default until your saved preferences load`}>
            <span className="member-push-category-name">{category}</span>
            <small>Enabled by default</small>
          </li>
        ))}
      </ul>
      <p className="member-push-note">A missing preference stays enabled by default; turning a category off changes only device delivery. Your inbox keeps every update either way.</p>
      <p className="member-push-note" dangerouslySetInnerHTML={{ __html: WEB_PUSH_UNAVAILABLE }} />
      <p className="member-push-unconfigured" dangerouslySetInnerHTML={{ __html: PUSH_UNCONFIGURED }} />
      <p className="member-push-note">Permission is asked only when you choose to enable notifications in the FitCruxx Android app under You → Notifications.</p>
      <p className="member-push-devices" aria-label="Linked devices">Linked devices: {`your Android app shows each device's last seen time and active state here once it appears.`}</p>
      <p className="member-push-note"><BellOff {...smallIcon} />Your {nouns.place} cannot reach a device that has push off — the in-app inbox is the source of truth.</p>
    </section>
  );
}
