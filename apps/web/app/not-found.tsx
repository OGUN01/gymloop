import { PRODUCT_NAME } from '@gymloop/shared';
import { RouteNotFound } from './route-state';

export default function NotFound() {
  return <RouteNotFound home="/" homeLabel="Go to Gymloop" className="system-page" brand={<span className="brand-link system-page-brand">{PRODUCT_NAME}</span>} />;
}
