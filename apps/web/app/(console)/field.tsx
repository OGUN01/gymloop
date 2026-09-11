import type { ReactNode } from 'react';

/**
 * The one labelled control wrapper every console form uses. Extracted to this
 * file because two screens had spelled the same lines out and `jscpd` called
 * the second copy a clone — and the `min-w-0` it carries is not decoration:
 * without it a browser squeezes a `select` inside a grid cell instead of
 * letting it scroll its own options.
 */
export function Field({ label, children }: { label: string; children: ReactNode }) {
  return <label className="block min-w-0 text-sm font-medium"><span className="mb-1 block">{label}</span>{children}</label>;
}

/**
 * The input classes every console control shares, exported from this
 * server-safe file (no 'use client' here) so a server component's filter
 * form and the client form components style a control identically. The
 * `bg-white` matters: the select it dresses sits on a tinted card, and the
 * browser's default select background reads as a disabled control.
 */
export const inputClass = 'min-h-11 w-full rounded-lg border border-neutral-300 bg-white px-3 py-2 text-base';

