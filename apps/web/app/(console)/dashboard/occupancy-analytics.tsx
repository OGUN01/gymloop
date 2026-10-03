import { exactFractionText, formatMoney as formatDisplayMoney, twoDigit, type BusinessNouns } from '@gymloop/shared';

import type { OccupancySnapshot } from '../../../lib/occupancy';

type HeatmapCellView = {
  weekday: number;
  hour: number;
  arrivals: number;
  todayArrivals?: number;
  eligibleDates: number;
  fraction: string | null;
  limited?: boolean;
  message?: string | null;
};

type ExcludedDateView = { localDate?: unknown; visits?: unknown };

type ClassFillView = {
  cohortSessions?: number;
  totalCapacity?: number;
  bookedFillFraction?: string | null;
  attendedCount?: number;
  noShowCount?: number;
  unmarkedCount?: number;
  markingCoverage?: string | null;
  limited?: boolean;
  message?: string | null;
};

const WEEKDAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function monthToDateLabel(month: string, through: string): string | null {
  return through.startsWith(month) ? 'Month to date' : null;
}

function collectionRows(snapshot: OccupancySnapshot): Array<{
  month: string;
  currency: string;
  collected: string;
  returned: string;
  net: string;
  classification: Record<string, unknown>;
  partial: string | null;
}> {
  return snapshot.months.map((raw) => {
    const row = raw as Record<string, unknown>;
    const month = String(row.month ?? '');
    return {
      month,
      currency: String(row.currency ?? ''),
      collected: String(row.collectedPaise ?? '0'),
      returned: String(row.returnedPaise ?? '0'),
      net: String(row.netPaise ?? '0'),
      classification: (row.classification ?? {}) as Record<string, unknown>,
      partial: monthToDateLabel(month, snapshot.through),
    };
  });
}

function heatmapRows(snapshot: OccupancySnapshot): HeatmapCellView[] {
  const heatmap = snapshot.heatmap;
  if (heatmap === null) return [];
  const cells = heatmap.cells;
  return Array.isArray(cells) ? cells as HeatmapCellView[] : [];
}

function classFill(snapshot: OccupancySnapshot): ClassFillView | null {
  return snapshot.classes as ClassFillView | null;
}

/** "No cohort" is reserved for a zero denominator: a zero-arrival hour with a
 * live denominator shows its exact 0 fraction (F4), and a limited cell's raw
 * numbers carry its own disclosure. */
function cellFractionLabel(cell: HeatmapCellView): string {
  if (cell.fraction !== null) return cell.fraction;
  if (cell.eligibleDates === 0) return 'No cohort';
  if (cell.limited === true) return `${cell.arrivals} of ${cell.eligibleDates}`;
  return exactFractionText(0, cell.eligibleDates) ?? 'No cohort';
}

function noEligibleDays(snapshot: OccupancySnapshot): boolean {
  return snapshot.heatmap !== null && snapshot.heatmap.noEligibleDays === true;
}

function excludedDateRows(snapshot: OccupancySnapshot): ExcludedDateView[] {
  const heatmap = snapshot.heatmap;
  if (heatmap === null || !Array.isArray(heatmap.excludedDates)) return [];
  return heatmap.excludedDates as ExcludedDateView[];
}

/** OCC-005's toggle: a plain GET form, no client state — the loader re-requests
 * the snapshot with p_exclude_holidays flipped; the hidden input makes the
 * off state submittable. */
function holidayToggle(snapshot: OccupancySnapshot) {
  return <form action="/dashboard" className="dashboard-range" method="get">
    <input name="occupancy" type="hidden" value="1" />
    <input name="from" type="hidden" value={snapshot.from} />
    <input name="through" type="hidden" value={snapshot.through} />
    {snapshot.branchId === null ? null : <input name="branch" type="hidden" value={snapshot.branchId} />}
    <input name="excludeHolidays" type="hidden" value="0" />
    <label><input defaultChecked={snapshot.excludeHolidays} name="excludeHolidays" type="checkbox" value="1" /> Exclude holidays</label>
    <button type="submit">Apply</button>
  </form>;
}

/** OCC-017: one truthful owner panel — zero, unavailable, excluded and unknown stay visibly distinct. */
export function OccupancyAnalytics({ snapshot, errorLabel, nouns }: {
  snapshot: OccupancySnapshot | null;
  errorLabel: string | null;
  nouns: BusinessNouns;
}) {
  if (errorLabel !== null) {
    return <section className="dashboard-panel" aria-labelledby="occupancy-heading">
      <div className="dashboard-panel-heading"><h2 id="occupancy-heading">Occupancy and collection</h2></div>
      <p role="alert" className="cl-alert">{errorLabel}</p>
    </section>;
  }
  if (snapshot === null) {
    return <section className="dashboard-panel" aria-labelledby="occupancy-heading">
      <div className="dashboard-panel-heading"><h2 id="occupancy-heading">Occupancy and collection</h2><p>Arrivals, monthly collection and booked fill for this {nouns.place}.</p></div>
      <div className="cl-empty dashboard-empty"><strong>Not loaded yet</strong><p>Choose a range to load one occupancy snapshot.</p></div>
      <form action="/dashboard" className="dashboard-range" method="get">
        <input name="occupancy" type="hidden" value="1" />
        <label>From <input name="from" type="date" /></label>
        <label>Through <input name="through" type="date" /></label>
        <button type="submit">Load occupancy snapshot</button>
      </form>
    </section>;
  }
  const rows = collectionRows(snapshot);
  const cells = heatmapRows(snapshot);
  const fill = classFill(snapshot);
  const excludedDates = excludedDateRows(snapshot);
  const scopeLabel = snapshot.branchId === null ? 'Whole gym' : 'Selected branch';
  return <section className="dashboard-panel" aria-labelledby="occupancy-heading">
    <div className="dashboard-panel-heading">
      <h2 id="occupancy-heading">Occupancy and collection</h2>
      <p>{snapshot.from} to {snapshot.through} · {scopeLabel}</p>
      <span className="cl-status" data-tone="warn">{snapshot.asOf === null ? 'Snapshot unavailable' : 'One snapshot'}</span>
    </div>
    <h3>Check-in arrivals</h3>
    {holidayToggle(snapshot)}
    {snapshot.excludeHolidays && excludedDates.length > 0 ? <ul className="cl-rows">
      {excludedDates.map((row, index) => <li key={`excluded-${index}`}>
        <span>{String(row.localDate ?? 'Unknown date')}</span>
        <span>Holiday excluded from this snapshot · {String(row.visits ?? '0')} arrivals excluded from the averages</span>
      </li>)}
    </ul> : null}
    {noEligibleDays(snapshot) ? <div className="cl-empty dashboard-empty"><strong>No eligible days</strong><p>Every date in this range is excluded, so no arrival average exists.</p></div> : null}
    {!noEligibleDays(snapshot) && cells.length === 0 ? <p className="dashboard-muted">No arrival cells in this snapshot.</p> : null}
    {cells.length > 0 ? <ul className="cl-rows">
      {cells.map((cell) => <li key={`${cell.weekday}-${cell.hour}`}>
        <span>{WEEKDAY_NAMES[cell.weekday] ?? 'Unknown'} {twoDigit(cell.hour)}:00</span>
        <span>{cell.arrivals} arrivals of {cell.eligibleDates} eligible dates · {cellFractionLabel(cell)}</span>
        {cell.todayArrivals !== undefined && cell.todayArrivals > 0 ? <span className="cl-status" data-tone="warn">{cell.todayArrivals} today (incomplete day)</span> : null}
        {cell.limited === true ? <span className="cl-status" data-tone="warn">{cell.message ?? 'Limited history'}</span> : null}
      </li>)}
    </ul> : null}
    <h3>Collection</h3>
    <p className="dashboard-muted">Whole gym · collection by paid month, per currency · net is net collection after completed returns{rows.some((row) => row.partial !== null) ? ' · current month is Month to date' : ''}</p>
    {rows.length === 0 ? <div className="cl-empty dashboard-empty"><strong>No collection recorded</strong><p>No arrived payments or completed returns in this range.</p></div> : <ul className="cl-rows">
      {rows.map((row) => <li key={`${row.month}-${row.currency}`}>
        <span>{row.month} · {row.currency}</span>
        <span>Collected {formatDisplayMoney(row.collected, row.currency)} · Net collection after completed returns {formatDisplayMoney(row.net, row.currency)}</span>
        <span>{String(row.classification.newMemberPaise ?? '0') === '0' && String(row.classification.renewalPaise ?? '0') === '0' ? '' : `New ${formatDisplayMoney(String(row.classification.newMemberPaise ?? '0'), row.currency)} · Renewal ${formatDisplayMoney(String(row.classification.renewalPaise ?? '0'), row.currency)}`}</span>
        <span>{row.partial ?? ''}</span>
      </li>)}
    </ul>}
    <p className="dashboard-muted">Split is {String(rows[0]?.classification.label ?? 'Membership linkage (derived classification)').toLowerCase()} · add-on and unallocated manual money stay separate.</p>
    <h3>Booked fill</h3>
    {fill === null ? <p className="dashboard-muted">No class facts in this snapshot.</p> : <>
      <ul className="cl-rows">
        <li><span>Booked fill</span><span>{fill.cohortSessions ?? 0} elapsed non-cancelled sessions · {fill.totalCapacity ?? 0} capacity · {fill.bookedFillFraction === null || fill.bookedFillFraction === undefined ? 'No cohort' : `${fill.bookedFillFraction} of capacity`}</span></li>
        <li><span>Marked presence</span><span>{fill.attendedCount ?? 0} attended · {fill.noShowCount ?? 0} no-show · {fill.unmarkedCount ?? 0} unmarked · coverage {fill.markingCoverage === null || fill.markingCoverage === undefined ? 'No cohort' : fill.markingCoverage}</span></li>
      </ul>
      {fill.limited === true ? <p className="cl-status" data-tone="warn">{fill.message ?? 'Limited history'}</p> : null}
      {fill.unmarkedCount !== undefined && fill.unmarkedCount > 0 ? <p className="dashboard-muted">Unmarked bookings still held seats; presence is counted only when the desk or trainer marked it.</p> : null}
    </>}
  </section>;
}
