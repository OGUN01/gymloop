import { UI_TOKENS } from '@gymloop/shared';

const cssName = (name: string) => name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
const colorVariables = Object.entries(UI_TOKENS.colors).flatMap(([theme, colors]) =>
  Object.entries(colors).map(([name, value]) => `--gymloop-color-${cssName(name)}-${theme}:${value}`),
).join(';');
const semanticVariables = (theme: keyof typeof UI_TOKENS.colors) => Object.keys(UI_TOKENS.colors[theme])
  .map((name) => `--gymloop-color-${cssName(name)}:var(--gymloop-color-${cssName(name)}-${theme})`).join(';');

/** Web-only adapter for the platform-neutral visual tokens. */
export function ThemeTokenStyle() {
  const { geometry, motion, typography } = UI_TOKENS;
  const tokenVariables = [
    ...geometry.spacing.map((value) => `--gymloop-space-${value}:${value}px`),
    ...Object.entries(geometry.radii).map(([name, value]) => `--gymloop-radius-${cssName(name)}:${value}px`),
    ...Object.entries(geometry.targets).map(([name, value]) => `--gymloop-target-${name}:${value}px`),
    ...Object.entries(motion).map(([name, value]) => `--gymloop-motion-${cssName(name)}:${value}ms`),
    ...Object.entries(typography).flatMap(([name, value]) => typeof value === 'object'
      ? Object.entries(value).map(([property, token]) => `--gymloop-type-${name}-${cssName(property)}:${token}px`)
      : [`--gymloop-type-${cssName(name)}:${value}`]),
  ].join(';');
  return <style>{`:root{${colorVariables};${tokenVariables};${semanticVariables('light')};color-scheme:light}[data-theme="light"]{${semanticVariables('light')};color-scheme:light}[data-theme="dark"]{${semanticVariables('dark')};color-scheme:dark}@media (prefers-color-scheme: dark){:root:not([data-theme]){${semanticVariables('dark')};color-scheme:dark}}@media (prefers-reduced-motion: reduce){*,*::before,*::after{animation-duration:0ms!important;transition-duration:0ms!important;scroll-behavior:auto!important}}@media (prefers-reduced-transparency: reduce){.gymloop-glass{backdrop-filter:none!important;background-color:var(--gymloop-color-surface)!important}}`}</style>;
}
