import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const directory = resolve(import.meta.dirname, '../../../../packages/shared/assets/fonts');
const HASH = '1c87b72912ef81b48ab4852976f3d5bf75c7205e0a58a97ffca947d171c722a7';
describe('INV-031 official shared Google Sans Medium asset', () => {
  it('bundles exact upstream v14.000 Medium bytes with truthful font metadata', () => {
    const font = readFileSync(resolve(directory, 'GoogleSans-Medium.ttf'));
    expect(createHash('sha256').update(font).digest('hex')).toBe(HASH);
    const tables = new Map<string, number>();
    for (let i = 0; i < font.readUInt16BE(4); i += 1) { const p = 12 + i * 16; tables.set(font.toString('ascii', p, p + 4), font.readUInt32BE(p + 8)); }
    expect(font.readUInt16BE(tables.get('OS/2')! + 4)).toBe(500);
    const name = tables.get('name')!; const strings = name + font.readUInt16BE(name + 4); const names: string[] = [];
    for (let i = 0; i < font.readUInt16BE(name + 2); i += 1) {
      const p = name + 6 + i * 12;
      if (font.readUInt16BE(p) !== 3) continue;
      const bytes = Buffer.from(font.subarray(strings + font.readUInt16BE(p + 10), strings + font.readUInt16BE(p + 10) + font.readUInt16BE(p + 8)));
      names.push(bytes.swap16().toString('utf16le'));
    }
    expect(names.join(' ')).toMatch(/Google Sans/); expect(names.join(' ')).toMatch(/Medium/);
  });
  it('ships SIL OFL 1.1 license and exact upstream provenance beside the font', () => {
    const text = readdirSync(directory).filter((name) => /\.(txt|md|json)$/i.test(name)).map((name) => readFileSync(resolve(directory, name), 'utf8')).join('\n');
    expect(text).toMatch(/SIL OPEN FONT LICENSE Version 1\.1/i);
    expect(text).toContain('https://github.com/googlefonts/googlesans');
    expect(text).toContain('v14.000'); expect(text).toContain(HASH);
  });
});
