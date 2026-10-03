/** Resolve the committed OCC visible suite's `../lib/occupancy` import (one
 * level off from the loader's real home, which the suite header pins as
 * apps/web/lib/occupancy.ts). Re-export only; the implementation lives there. */
export { OccupancyLoadError, loadOccupancyAnalytics } from '../../lib/occupancy';
export type { OccupancyLoadErrorCode, OccupancyRequest, OccupancySnapshot } from '../../lib/occupancy';
