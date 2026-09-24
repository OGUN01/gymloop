'use client';

import Link from 'next/link';
import { BadgeCheck, ChevronDown, ChevronRight, Monitor, Moon, Settings, Sun } from 'lucide-react';
import { AVATAR_INITIALS_MAX, formatPhone, UI_TOKENS } from '@gymloop/shared';
import { useTheme } from 'next-themes';
import { useEffect, useRef, useState } from 'react';
import { StatusWord } from '../status-word';
import { memberGymName } from './member-ui';

type Profile = { full_name: string; email: string | null; phone: string | null; member_code: string | null; gymName: string; gymCode: string; branchName: string };
type Membership = { planName: string; status: string } | null;

const small = { 'aria-hidden': true, size: UI_TOKENS.icons.controlSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;
const large = { 'aria-hidden': true, size: UI_TOKENS.icons.navigationSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;
const APPEARANCE_CHOICES = [
  { name: 'System', value: 'system', hint: 'Match this device', Icon: Monitor },
  { name: 'Light', value: 'light', hint: 'Warm paper, dark ink', Icon: Sun },
  { name: 'Dark', value: 'dark', hint: 'Easier in a dim gym', Icon: Moon },
] as const;

export default function YouSettings({ profile, membership }: { profile: Profile; membership: Membership }) {
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [appearanceExpanded, setAppearanceExpanded] = useState(true);
  const [hasMounted, setHasMounted] = useState(false);
  const closeRef = useRef<HTMLButtonElement>(null);
  const { theme, setTheme } = useTheme();
  useEffect(() => { setHasMounted(true); }, []);
  useEffect(() => {
    if (!settingsOpen) return undefined;
    closeRef.current?.focus();
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') setSettingsOpen(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [settingsOpen]);
  const appearanceSummary = !hasMounted ? 'Loading appearance' : theme === 'dark' ? 'Dark' : theme === 'light' ? 'Light' : 'System';
  const contactSummary = profile.email ?? profile.phone ?? 'Available after sign-in';
  const gymSummary = `${memberGymName({ name: profile.gymName, branchName: profile.branchName })} · ${profile.gymCode}`;
  const personalSummary = profile.phone ? formatPhone(profile.phone) : profile.email ?? 'Available after sign-in';
  const membershipSummary = membership ? `${membership.planName} · ${membership.status.replaceAll('_', ' ')}` : 'No membership is visible';
  const initials = profile.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('');
  const openSettings = () => { setAppearanceExpanded(true); setSettingsOpen(true); };
  return <>
    <button type="button" className="member-settings-trigger" aria-label="Open settings" title="Settings" onClick={openSettings}><Settings {...large} /></button>
    <section className="member-profile" aria-label="Your profile">
      <div className="member-avatar" aria-hidden="true">{initials}</div>
      <div>
        <h1 className="member-profile-name">{profile.full_name}</h1>
        <p className="member-verified"><BadgeCheck {...small} />Verified member</p>
        <small>{gymSummary}</small>
        <small>{contactSummary}</small>
      </div>
    </section>
    <h2 className="cl-eyebrow member-eyebrow member-account-eyebrow">Account</h2>
    <ul className="member-account-list" aria-label="Account">
      <li aria-label={`Personal details, ${personalSummary}`}><span className="member-account-row"><strong>Personal details</strong><small>{personalSummary}</small></span></li>
      <li aria-label={`Membership, ${membershipSummary}`}><Link className="member-account-row" href="/member/my-gym#membership"><strong>Membership</strong><span className="member-account-value">{membership ? <>{membership.planName}<StatusWord status={membership.status} /></> : 'None visible'}</span><ChevronRight {...small} /></Link></li>
      <li aria-label={`Gym, ${profile.branchName} branch`}><Link className="member-account-row" href="/member/my-gym"><strong>Gym</strong><small>{profile.branchName}</small><ChevronRight {...small} /></Link></li>
      <li aria-label={`Appearance, ${appearanceSummary}`}><button type="button" className="member-account-row" aria-label={`Appearance, ${appearanceSummary}`} onClick={openSettings}><strong>Appearance</strong><small>{appearanceSummary}</small><ChevronRight {...small} /></button></li>
    </ul>
    {settingsOpen ? <div className="member-sheet-backdrop" role="presentation" onClick={() => setSettingsOpen(false)}><section className="member-settings-sheet" role="dialog" aria-modal="true" aria-labelledby="member-settings-title" onClick={(event) => event.stopPropagation()}>
      <header className="member-sheet-header"><h2 id="member-settings-title" className="cl-display">Settings</h2><button ref={closeRef} type="button" className="member-sheet-done" onClick={() => setSettingsOpen(false)}>Done</button></header>
      <button type="button" className="member-sheet-toggle" aria-label={`Appearance, ${appearanceSummary}`} aria-expanded={appearanceExpanded} aria-controls="member-appearance-choices" onClick={() => setAppearanceExpanded((open) => !open)}>
        <strong>Appearance</strong><small>{appearanceSummary}</small><ChevronDown {...small} />
      </button>
      {appearanceExpanded ? <div id="member-appearance-choices" className="member-appearance-choices" role="radiogroup" aria-label="Appearance">
        {APPEARANCE_CHOICES.map(({ name, value, hint, Icon }) => <label key={value} className="member-appearance-choice">
          <input type="radio" name="member-appearance" value={value} checked={hasMounted && (theme ?? 'system') === value} onChange={() => setTheme(value)} />
          <Icon {...large} />
          <span><strong>{name}</strong><small>{hint}</small></span>
          <i aria-hidden="true" />
        </label>)}
      </div> : null}
    </section></div> : null}
  </>;
}
