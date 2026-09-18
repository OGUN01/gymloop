'use client';

import { Monitor, Moon, Sun } from 'lucide-react';
import { UI_TOKENS } from '@gymloop/shared';
import { ThemeProvider, useTheme } from 'next-themes';
import { useEffect, useState, type ReactNode } from 'react';

export function AppThemeProvider({ children }: { children: ReactNode }) {
  return <ThemeProvider attribute="data-theme" defaultTheme="system" disableTransitionOnChange enableSystem storageKey="gymloop-theme">{children}</ThemeProvider>;
}

const choices = [
  { name: 'System', value: 'system', Icon: Monitor }, { name: 'Light', value: 'light', Icon: Sun }, { name: 'Dark', value: 'dark', Icon: Moon },
] as const;

/** Appearance selector with an inert, equal-geometry server placeholder. */
export function ThemeControl() {
  if (typeof window === 'undefined') {
    return <div aria-label="Appearance" aria-hidden="true" data-theme-placeholder className="theme-control theme-control-placeholder" />;
  }
  return <MountedThemeControl />;
}

function MountedThemeControl() {
  const { theme, resolvedTheme, setTheme } = useTheme();
  const [hasMounted, setHasMounted] = useState(false);
  useEffect(() => { setHasMounted(true); }, []);
  if (!hasMounted || theme === undefined || resolvedTheme === undefined) {
    return <div aria-label="Appearance" aria-hidden="true" data-theme-placeholder className="theme-control theme-control-placeholder" />;
  }
  return <div aria-label="Appearance" className="theme-control" role="group">{choices.map(({ name, value, Icon }) => (
    <button aria-pressed={theme === value} className="theme-choice" key={value} onClick={() => setTheme(value)} type="button">
      <Icon aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /><span>{name}</span>
    </button>
  ))}</div>;
}
