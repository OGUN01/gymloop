'use client';
import { useEffect, useState } from 'react';

/** Browser connectivity for presentation; commands retain their own live guards. */
export function useBrowserOnline() {
  const [online, setOnline] = useState(true);
  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    const connectivityEvents = ['online', 'offline'] as const;
    update();
    for (const event of connectivityEvents) window.addEventListener(event, update);
    return () => {
      for (const event of connectivityEvents) window.removeEventListener(event, update);
    };
  }, []);
  return online;
}
