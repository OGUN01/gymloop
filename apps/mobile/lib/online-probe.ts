import { useEffect, useState } from 'react';

/**
 * The one runtime connectivity probe for mobile surfaces (SLF-017/TRV-008):
 * probed at runtime so the importing module pulls no network dependency at
 * load time, re-probed whenever the caller's key changes, and `false` on any
 * probe failure — surfaces treat unknown as offline, never as online.
 */
export function useRuntimeOnline(key?: unknown): boolean {
  const [online, setOnline] = useState(false);
  useEffect(() => {
    let active = true;
    void import('expo-network').then(Network => Network.getNetworkStateAsync()).then(network => {
      if (active) setOnline(network.isConnected === true && network.isInternetReachable === true);
    }).catch(() => { if (active) setOnline(false); });
    return () => { active = false; };
  }, [key]);
  return online;
}