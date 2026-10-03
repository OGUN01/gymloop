'use client';
import { RouteError } from '../../route-state';
export default function Error({ reset }: { reset(): void }) { return <RouteError reset={reset} home="/classes" homeLabel="Back" className="cl-page" />; }
