'use client';

import Link from 'next/link';
import { ArrowLeft, BadgeCheck, ChevronRight, Settings, X } from 'lucide-react';
import { AVATAR_INITIALS_MAX, formatPhone, UI_TOKENS } from '@gymloop/shared';
import { useTheme } from 'next-themes';
import { useEffect, useRef, useState } from 'react';
import { ThemeControl } from '../theme-provider';

type Profile = { full_name: string; email: string | null; phone: string | null; member_code: string | null; gymName: string; gymCode: string };

const small = { 'aria-hidden': true, size: UI_TOKENS.icons.controlSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;
const large = { 'aria-hidden': true, size: UI_TOKENS.icons.navigationSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;

export default function YouSettings({ profile, membershipSummary }: { profile: Profile; membershipSummary: string }) {
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [appearanceOpen, setAppearanceOpen] = useState(false);
  const [hasMounted, setHasMounted] = useState(false);
  const closeRef = useRef<HTMLButtonElement>(null);
  const { theme } = useTheme();
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
  const gymSummary = `${profile.gymName} · ${profile.gymCode}`;
  const personalSummary = profile.phone ? formatPhone(profile.phone) : profile.email ?? 'Available after sign-in';
  const initials = profile.full_name.split(' ').filter(Boolean).slice(0, AVATAR_INITIALS_MAX).map((part) => part.charAt(0)).join('');
  const openAppearance = () => { setAppearanceOpen(true); setSettingsOpen(true); };
  return <>
    <button type="button" className="member-settings-trigger" aria-label="Open settings" onClick={() => setSettingsOpen(true)}><Settings {...large} /></button>
    <section className="member-profile" aria-label="Your profile">
      <div className="member-avatar" aria-hidden="true">{initials}</div>
      <div>
        <h1 className="member-profile-name">{profile.full_name}</h1>
        <p className="member-verified"><BadgeCheck {...small} />Verified member</p>
        <small>{gymSummary}</small>
        <small>{contactSummary}</small>
      </div>
    </section>
    <h2 className="cl-eyebrow member-eyebrow">Account</h2>
    <ul className="member-account-list" aria-label="Account">
      <li aria-label={`Personal details, ${personalSummary}`}><span className="member-account-row"><strong>Personal details</strong><small>{personalSummary}</small></span></li>
      <li aria-label={`Membership, ${membershipSummary}`}><Link className="member-account-row" href="/member/my-gym"><strong>Membership</strong><small>{membershipSummary}</small><ChevronRight {...small} /></Link></li>
      <li aria-label={`Gym, ${gymSummary}`}><Link className="member-account-row" href="/member/my-gym"><strong>Gym</strong><small>Code {profile.gymCode}</small><ChevronRight {...small} /></Link></li>
      <li aria-label={`Appearance, ${appearanceSummary}`}><button type="button" className="member-account-row" onClick={openAppearance}><strong>Appearance</strong><small>{appearanceSummary}</small><ChevronRight {...small} /></button></li>
    </ul>
    {settingsOpen ? <div className="member-sheet-backdrop" role="presentation" onClick={() => setSettingsOpen(false)}><section className="member-settings-sheet" role="dialog" aria-modal="true" aria-labelledby="member-settings-title" onClick={(event) => event.stopPropagation()}>
      <header><button ref={closeRef} type="button" aria-label="Close settings" className="member-sheet-icon" onClick={() => setSettingsOpen(false)}><X {...large} /></button><h2 id="member-settings-title">Settings</h2><span /></header>
      {appearanceOpen
        ? <><button type="button" className="member-sheet-back" onClick={() => setAppearanceOpen(false)}><ArrowLeft {...small} />Back to settings</button><div className="member-sheet-section"><h3 className="cl-eyebrow">Appearance</h3><p>Choose how Gymloop looks on this device.</p><ThemeControl /></div></>
        : <div className="member-sheet-list"><button type="button" onClick={() => setAppearanceOpen(true)}><span><strong>Appearance</strong><small>{appearanceSummary}</small></span><ChevronRight {...small} /></button></div>}
    </section></div> : null}
  </>;
}
