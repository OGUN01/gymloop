'use client';
import { useState } from 'react';
export function ShopImage({ imageUrl }: { imageUrl: string | null }) {
  const [failed, setFailed] = useState(false);
  return imageUrl && !failed ? <img className="rounded-xl object-cover h-40 w-full" src={imageUrl} alt="" onError={() => setFailed(true)} /> : <div aria-hidden="true" className="cl-muted rounded-xl bg-[var(--gymloop-color-surface)] min-h-40 flex items-center justify-center">◇</div>;
}
