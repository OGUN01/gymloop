'use client';
import { RouteError } from '../../route-state';
export default function Error({ reset }: { reset(): void }) { return <RouteError reset={reset} home="/member" homeLabel="Back" className="member-route member-portal" />; }
