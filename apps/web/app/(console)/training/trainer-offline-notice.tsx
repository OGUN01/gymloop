'use client';

import { forwardRef } from 'react';
import { OfflineNotice } from '../../offline-notice';

/**
 * TRV-008's web offline banner (frozen trainer-view proposal), now the shared
 * OfflineNotice wrapped with TRV's frozen copy and its Training refresh
 * affordance. The forwardRef boundary keeps this a client-side concern —
 * server rendering of the day view never invokes its effects.
 */
export const TrainerOfflineNotice = forwardRef<HTMLParagraphElement, { refreshHref?: string }>(function TrainerOfflineNotice({ refreshHref = '/training' }, ref) {
  return <OfflineNotice ref={ref} copy="You're offline. Connect to load your sessions." refreshHref={refreshHref} />;
});