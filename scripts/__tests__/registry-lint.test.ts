import { describe, expect, it } from 'vitest';
import { findUnregisteredExports } from '../registry-lint.mjs';

describe('findUnregisteredExports', () => {
  it('flags a named export missing from the registry', () => {
    const files = [{ path: 'packages/shared/src/config/x.ts', content: 'export const FOO = 1;\n' }];
    const missing = findUnregisteredExports(files, '# Registry\nnothing relevant here\n');
    expect(missing).toEqual([{ path: 'packages/shared/src/config/x.ts', name: 'FOO' }]);
  });

  it('passes when the export name appears in the registry', () => {
    const files = [{ path: 'packages/shared/src/config/x.ts', content: 'export const FOO = 1;\n' }];
    const missing = findUnregisteredExports(files, '| `FOO` | some/path | purpose | user |\n');
    expect(missing).toEqual([]);
  });

  it('ignores test files, the generated db types file, and non-package/app paths', () => {
    const files = [
      { path: 'packages/shared/src/config/__tests__/x.test.ts', content: 'export const BAR = 1;\n' },
      { path: 'packages/db/types/database.ts', content: 'export const BAZ = 1;\n' },
      { path: 'scripts/other.mjs', content: 'export const QUX = 1;\n' },
    ];
    expect(findUnregisteredExports(files, '# empty registry\n')).toEqual([]);
  });

  it('flags `export async function` — async sits between export and function', () => {
    const files = [{ path: 'apps/web/app/api/handler.ts', content: 'export async function POST() {}\n' }];
    const missing = findUnregisteredExports(files, '# empty registry\n');
    expect(missing).toEqual([{ path: 'apps/web/app/api/handler.ts', name: 'POST' }]);
  });

  it('flags braced re-exports, including renamed ones', () => {
    const files = [
      { path: 'packages/shared/src/a.ts', content: "export { alpha, beta as gamma } from './x';\n" },
    ];
    const missing = findUnregisteredExports(files, '# empty registry\n');
    expect(missing.map((m) => m.name).sort()).toEqual(['alpha', 'gamma']);
  });

  it('requires a backticked registry cell, not a bare substring match', () => {
    const files = [{ path: 'packages/shared/src/a.ts', content: 'export const Role = 1;\n' }];
    // "Role" appears in prose but not as a registered `Role` cell.
    const prose = 'Every Role in the system is fixed in v1.\n';
    expect(findUnregisteredExports(files, prose)).toEqual([
      { path: 'packages/shared/src/a.ts', name: 'Role' },
    ]);
    // Now genuinely registered.
    expect(findUnregisteredExports(files, '| `Role` | path | purpose | user |\n')).toEqual([]);
  });

  it('ignores Next.js route-convention files but still flags a real component export', () => {
    const files = [
      { path: 'apps/web/app/page.tsx', content: 'export const metadata = {};\n' },
      { path: 'apps/web/app/some-widget.tsx', content: 'export function Widget() {}\n' },
    ];
    const missing = findUnregisteredExports(files, '# empty registry\n');
    expect(missing).toEqual([{ path: 'apps/web/app/some-widget.tsx', name: 'Widget' }]);
  });
});
