import { readdir, readFile } from 'node:fs/promises';
import { dirname, extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const HOLDOUT_DIRECTORY = dirname(fileURLToPath(import.meta.url));
const WEB_ROOT = resolve(HOLDOUT_DIRECTORY, '../../../apps/web');
const SOURCE_DIRECTORIES = ['app', 'lib'];
const SOURCE_EXTENSIONS = new Set(['.js', '.jsx', '.ts', '.tsx']);
const TEST_DIRECTORY = '__tests__';

async function sourceFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const entryPath = join(directory, entry.name);

      if (entry.isDirectory()) {
        return entry.name === TEST_DIRECTORY ? [] : sourceFiles(entryPath);
      }

      return SOURCE_EXTENSIONS.has(extname(entry.name)) ? [entryPath] : [];
    }),
  );

  return nested.flat();
}

async function webSource() {
  const files = (
    await Promise.all(
      SOURCE_DIRECTORIES.map((directory) => sourceFiles(join(WEB_ROOT, directory))),
    )
  ).flat();

  return Promise.all(
    files.map(async (file) => ({ file, content: await readFile(file, 'utf8') })),
  );
}

describe('PAY-012 manual-only payment release holdout', () => {
  it('offers no Razorpay charge or provider-callback surface', async () => {
    const source = await webSource();
    const providerIntegration = /\bnew\s+razorpay\b|\bfrom\s+['"]razorpay['"]|\brequire\(\s*['"]razorpay['"]\s*\)|\brazorpay\s*\.\s*(?:orders|payments|subscriptions|webhooks)\b|https?:\/\/[^'"\s]*razorpay\.(?:com|in)\b/i;
    const providerRoute = /[\\/]api[\\/](?:[^\\/]+[\\/])*(?:razorpay|webhooks?|callbacks?|checkout|charges?|payment-intents?)[\\/]/i;
    const offenders = source
      .filter(({ file, content }) =>
        providerIntegration.test(content) || providerRoute.test(relative(WEB_ROOT, file)),
      )
      .map(({ file }) => file);

    expect(offenders).toEqual([]);
  });

  it('does not contain raw card or UPI credential capture or storage fields', async () => {
    const source = await webSource();
    const credentialField = /\b(?:card[\s_-]*(?:number|pan|cvv|cvc|expiry|expiration)|(?:upi|vpa)[\s_-]*(?:pin|password|credential|secret)|upi[\s_-]*id)\b/i;
    const offenders = source
      .filter(({ content }) => credentialField.test(content))
      .map(({ file }) => file);

    expect(offenders).toEqual([]);
  });
});
