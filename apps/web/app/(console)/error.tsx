'use client';

import { RouteError } from '../route-state';

export default function ConsoleError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <RouteError reset={reset} home="/console" homeLabel="Back to members" className="cl-page" />;
}
