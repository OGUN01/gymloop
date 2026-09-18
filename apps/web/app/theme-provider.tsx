'use client';

import { Monitor, Moon, Sun } from 'lucide-react';
import { ThemeProvider, useTheme } from 'next-themes';
import type { ReactNode } from 'react';

export function AppThemeProvider({ children }: { children: ReactNode }) {
  return <ThemeProvider attribute="data-theme" defaultTheme="system" enableSystem storageKey="gymloop-theme">{children}</ThemeProvider>;
}

const choices = [
  { name: 'System', value: 'system', Icon: Monitor }, { name: 'Light', value: 'light', Icon: Sun }, { name: 'Dark', value: 'dark', Icon: Moon },
] as const;

/** Appearance selector with an inert, equal-geometry server placeholder. */
export function ThemeControl() {
  const { theme, resolvedTheme, setTheme } = useTheme();
  if (theme === undefined || resolvedTheme === undefined) {
    return <div aria-label="Appearance" aria-hidden="true" data-theme-placeholder className="theme-control theme-control-placeholder" />;
  }
  return <div aria-label="Appearance" className="theme-control" role="group">{choices.map(({ name, value, Icon }) => (
    <button aria-pressed={theme === value} className="theme-choice" key={value} onClick={() => setTheme(value)} type="button">
      <Icon aria-hidden="true" size={16} strokeWidth={1.8} /><span>{name}</span>
    </button>
  ))}</div>;
}
