'use client';

import localFont from 'next/font/local';
import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { GOOGLE_BRAND_COLORS, GOOGLE_PROVIDER_METRICS } from '@gymloop/shared';
import { GoogleGlyph } from './google-glyph';

const googleSans = localFont({
  src: '../../../packages/shared/assets/fonts/GoogleSans-Medium.ttf',
  weight: '500',
  style: 'normal',
  display: 'block',
  fallback: [],
});

/** Only font availability gates submission; the enclosing form owns authentication. */
export function GoogleProviderButton({ label = 'Continue with Google', className = '', disabled = false }: {
  label?: 'Continue with Google' | 'Sign in with Google';
  className?: string;
  disabled?: boolean;
}) {
  const [availability, setAvailability] = useState<'loading' | 'ready' | 'failed'>('loading');
  const active = useRef(true);
  const query = `${GOOGLE_PROVIDER_METRICS.fontWeight} ${GOOGLE_PROVIDER_METRICS.fontSize}px ${googleSans.style.fontFamily}`;
  async function loadFont() {
    setAvailability('loading');
    try {
      const faces = await document.fonts.load(query, label);
      if (active.current) setAvailability(faces.length > 0 && document.fonts.check(query, label) ? 'ready' : 'failed');
    } catch {
      if (active.current) setAvailability('failed');
    }
  }
  function retryFont() {
    // Browsers retain a rejected CSS FontFace promise. Reload the same page to
    // recreate that face and refetch its bundled asset, preserving invite URLs
    // and cookies without submitting the enclosing authentication form.
    const failedFace = Array.from(document.fonts).some(face => face.status === 'error' && googleSans.style.fontFamily.includes(face.family));
    if (failedFace) {
      window.location.reload();
      return;
    }
    void loadFont();
  }
  useEffect(() => {
    active.current = true;
    void loadFont();
    return () => { active.current = false; };
  }, [query, label]);
  const metrics = {
    '--google-provider-size': `${GOOGLE_PROVIDER_METRICS.fontSize / GOOGLE_PROVIDER_METRICS.remBase}rem`,
    '--google-provider-line': GOOGLE_PROVIDER_METRICS.lineHeight / GOOGLE_PROVIDER_METRICS.fontSize,
    '--google-provider-weight': GOOGLE_PROVIDER_METRICS.fontWeight,
    '--google-provider-start': `${GOOGLE_PROVIDER_METRICS.paddingStart}px`,
    '--google-provider-gap': `${GOOGLE_PROVIDER_METRICS.iconGap}px`,
    '--google-provider-end': `${GOOGLE_PROVIDER_METRICS.paddingEnd}px`,
    '--google-provider-target': `${GOOGLE_PROVIDER_METRICS.webTarget}px`,
    '--google-provider-light-background': GOOGLE_BRAND_COLORS.light.background,
    '--google-provider-light-foreground': GOOGLE_BRAND_COLORS.light.foreground,
    '--google-provider-dark-background': GOOGLE_BRAND_COLORS.dark.background,
    '--google-provider-dark-foreground': GOOGLE_BRAND_COLORS.dark.foreground,
  } as CSSProperties;
  return <>
    <button type="submit" className={`sign-in-provider ${googleSans.className} ${className}`} style={metrics} disabled={disabled || availability !== 'ready'}>
      <GoogleGlyph /><span>{label}</span>
    </button>
    {availability === 'loading' ? <p role="status" className="cl-hint">Preparing Google sign-in…</p> : null}
    {availability === 'failed' ? <div className="cl-hint" role="alert"><p>Google sign-in could not load. Try again to reload this page and prepare the button.</p><button type="button" className="cl-btn" onClick={retryFont}>Try again</button></div> : null}
  </>;
}
