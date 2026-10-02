import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
const mobile = (path: string) => readFileSync(new URL(`../../../mobile/${path}`, import.meta.url), 'utf8');
describe('PLC-016/018/019 native consumer wiring', () => {
  it('Gym mounts the second disclosure and calls its hook before early returns', () => {
    const source = mobile('app/(member)/gym.tsx');
    const call = source.search(/useMemberPlans\(openSection\s*===\s*['"]plans['"]\)/);
    expect(call).toBeGreaterThan(source.indexOf('markError'));
    expect(call).toBeLessThan(source.search(/if\s*\([^)]*\)\s*(?:\{\s*)?return/));
    expect(source).toContain('Plans & prices'); expect(source).toMatch(/toggle\(['"]plans['"]\)/);
    expect(source.indexOf('Plans & prices')).toBeLessThan(source.indexOf('Attendance history'));
    expect(source).toContain('PlanCatalogueBody'); expect(source).not.toContain('readPlanCatalogue');
  });
  it('hook reads caller-scoped data, classifies network failure and guards newer request/scope', () => {
    const hook = mobile('lib/use-member-plans.ts');
    expect(hook).toContain('expo-network'); expect(hook).toContain('readPlanCatalogue');
    expect(hook).toContain('isConnected'); expect(hook).toContain('isInternetReachable');
    for (const key of ['userId', 'tenantId', 'memberId']) expect(hook).toContain(key);
    expect(hook).toMatch(/identity\.kind\s*!==?\s*['"]member['"]|identity\.kind\s*===\s*['"]member['"]/);
    expect(hook).toMatch(/type:\s*['"]reset['"]/);
    expect(hook).toMatch(/useRef/);
    // Catalog presence is structural evidence; actual racing responses are
    // exercised by a hook runner, not claimed proven by this source audit.
  });
  it.each(['lib/use-member-plans.ts', 'lib/plan-catalogue-state.ts', 'components/plan-catalogue.tsx'])('%s adds no persisted or mutating path', (file) => {
    const source = mobile(file);
    expect(source).not.toMatch(/SecureStore|AsyncStorage|new\s+Map\s*\(|api\.post|console\.(?:log|warn|error)/);
    expect(source).not.toMatch(/\b(?:buy|purchase|upgrade|subscribe|checkout)\b/i);
  });
  it('native entry announces name, price, duration using the shared helper copy', () => {
    const source = mobile('components/plan-catalogue.tsx');
    expect(source).toContain('accessibilityLabel'); expect(source).toContain('formatMoney');
    expect(source).toContain('planDurationLabel'); expect(source).toContain('planGstLabel');
    expect(source).toContain('heldPlanNotice'); expect(source).toContain('ActivityIndicator');
    expect(source).toContain('StateMessage'); expect(source).toContain('ErrorRetry');
  });
});
