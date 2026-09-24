import { RouteNotFound } from '../route-state';

export default function ConsoleNotFound() {
  return <RouteNotFound home="/console" homeLabel="Back to members" title="Record not found" />;
}
