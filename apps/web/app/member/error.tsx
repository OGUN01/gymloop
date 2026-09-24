'use client';

import { RouteError } from '../route-state';

export default function MemberError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <RouteError reset={reset} home="/member" homeLabel="Back to home" className="member-route member-portal" />;
}
