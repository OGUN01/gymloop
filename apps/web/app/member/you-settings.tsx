'use client';

import { ArrowLeft, ChevronRight, Settings, X } from 'lucide-react';
import { UI_TOKENS } from '@gymloop/shared';
import { useState } from 'react';
import { ThemeControl } from '../theme-provider';

type Profile = { full_name: string; email: string | null; phone: string | null; member_code: string | null; gymName: string; gymCode: string };

export default function YouSettings({ profile }: { profile: Profile }) {
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [appearanceOpen, setAppearanceOpen] = useState(false);
  return <>
    <div className="member-you-summary"><section className="member-profile"><div className="member-avatar" aria-hidden="true">{profile.full_name.slice(0, 1)}</div><div><strong>{profile.full_name}</strong><p>{profile.email ?? profile.phone ?? 'Member account'}</p><small>{profile.gymName} · {profile.gymCode}</small></div></section><button type="button" className="member-settings-trigger" aria-label="Open settings" onClick={() => setSettingsOpen(true)}><Settings aria-hidden="true" size={UI_TOKENS.icons.navigationSize} /><span className="sr-only">Settings</span></button></div>
    {settingsOpen ? <div className="member-sheet-backdrop" role="presentation" onClick={() => setSettingsOpen(false)}><section className="member-settings-sheet" role="dialog" aria-modal="true" aria-labelledby="member-settings-title" onClick={(event) => event.stopPropagation()}>
      <header><button type="button" aria-label="Close settings" className="member-sheet-icon" onClick={() => setSettingsOpen(false)}><X aria-hidden="true" size={UI_TOKENS.icons.controlSize} /></button><h2 id="member-settings-title">Settings</h2><span /></header>
      {appearanceOpen ? <><button type="button" className="member-sheet-back" onClick={() => setAppearanceOpen(false)}><ArrowLeft aria-hidden="true" size={UI_TOKENS.icons.controlSize} />Appearance</button><div className="member-sheet-section"><p>Choose how Gymloop looks on this device.</p><ThemeControl /></div></> : <div className="member-sheet-list"><button type="button" onClick={() => setAppearanceOpen(true)}><span><strong>Appearance</strong><small>System, light, or dark</small></span><ChevronRight aria-hidden="true" size={UI_TOKENS.icons.controlSize} /></button></div>}
    </section></div> : null}
  </>;
}
