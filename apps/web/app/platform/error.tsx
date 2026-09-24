'use client';

import { RouteError } from '../route-state';

export default function PlatformError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <RouteError reset={reset} home="/platform" homeLabel="Back to gyms" className="cl-page" />;
}
