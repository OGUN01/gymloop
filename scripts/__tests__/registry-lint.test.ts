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

  it('flags `export default function` — default sits before the declaration keyword', () => {
    const files = [{ path: 'packages/shared/src/widget.ts', content: 'export default function Widget() {}\n' }];
    expect(findUnregisteredExports(files, '# empty registry\n')).toEqual([
      { path: 'packages/shared/src/widget.ts', name: 'Widget' },
    ]);
  });

  it('covers supabase/functions/** — Phase 5 webhooks must not be invisible to the gate', () => {
    const files = [
      { path: 'supabase/functions/razorpay-webhook/index.ts', content: 'export async function handler() {}\n' },
    ];
    expect(findUnregisteredExports(files, '# empty registry\n')).toEqual([
      { path: 'supabase/functions/razorpay-webhook/index.ts', name: 'handler' },
    ]);
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

  it('flags an indented export — the anchor must not require column 0', () => {
    const files = [{ path: 'packages/shared/src/a.ts', content: '  export const gp3Indented = 1;\n' }];
    expect(findUnregisteredExports(files, '# empty registry\n')).toEqual([
      { path: 'packages/shared/src/a.ts', name: 'gp3Indented' },
    ]);
  });

  it('flags braced type re-exports: `export type { T }`', () => {
    const files = [{ path: 'packages/shared/src/a.ts', content: "export type { Gp3T } from './t';\nexport type { Gp3U as Gp3V };\n" }];
    expect(findUnregisteredExports(files, '# empty registry\n').map((m) => m.name)).toEqual(['Gp3T', 'Gp3V']);
  });

  it('flags namespace re-exports: `export * as ns from`', () => {
    const files = [{ path: 'packages/shared/src/a.ts', content: "export * as gp3ns from './d';\n" }];
    expect(findUnregisteredExports(files, '# empty registry\n')).toEqual([
      { path: 'packages/shared/src/a.ts', name: 'gp3ns' },
    ]);
  });

  it('flags destructured declarations: object and array patterns, const/let/var', () => {
    const files = [
      {
        path: 'packages/shared/src/a.ts',
        content: [
          'export const { gp3A, gp3B: gp3C, gp3D = 1 } = obj;',
          'export let [gp3E, gp3F] = arr;',
          'export var {\n  gp3G,\n  gp3H,\n} = obj;',
          '',
        ].join('\n'),
      },
    ];
    expect(findUnregisteredExports(files, '# empty registry\n').map((m) => m.name)).toEqual([
      'gp3A', 'gp3C', 'gp3D', 'gp3E', 'gp3F', 'gp3G', 'gp3H',
    ]);
    // gp3B is the source key, not the bound name — registering the bound names is enough.
    expect(
      findUnregisteredExports(files, '`gp3A` `gp3C` `gp3D` `gp3E` `gp3F` `gp3G` `gp3H`\n'),
    ).toEqual([]);
  });

  it('exempts only framework-mandated names in route-convention files, not reusable helpers', () => {
    const files = [
      {
        path: 'apps/web/app/api/members/route.ts',
        content: [
          'export const runtime = "edge";',
          'export const dynamic = "force-dynamic";',
          'export async function GET() {}',
          'export async function POST() {}',
          'export function gp3ListMembers() {}',
          '',
        ].join('\n'),
      },
      {
        path: 'apps/web/app/layout.tsx',
        content: 'export const metadata = {};\nexport async function generateMetadata() {}\nexport default function RootLayout() {}\n',
      },
    ];
    expect(findUnregisteredExports(files, '# empty registry\n')).toEqual([
      { path: 'apps/web/app/api/members/route.ts', name: 'gp3ListMembers' },
    ]);
    // Outside apps/*/app/, a file merely named route.ts gets no exemption.
    expect(
      findUnregisteredExports([{ path: 'packages/shared/src/route.ts', content: 'export const GET = 1;\n' }], '# empty\n'),
    ).toEqual([{ path: 'packages/shared/src/route.ts', name: 'GET' }]);
  });
});
