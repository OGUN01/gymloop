/// <reference types="node" />
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const mobileRoot = new URL('../../', import.meta.url);
const loadJson = (name: string): Record<string, unknown> => JSON.parse(readFileSync(new URL(name, mobileRoot), 'utf8'));

describe('NFC-001/002 public Android configuration', () => {
  it('retains the approved application, EAS and scheme identity', () => {
    const { expo } = loadJson('app.json') as { expo: { android: { package: string }; extra: { eas: { projectId: string } }; scheme: string } };
    expect(expo.android.package).toBe('in.fitcruxx.app');
    expect(expo.extra.eas.projectId).toBe('3708f347-96ac-4236-a74c-95808210292b');
    expect(expo.scheme).toBe('fitcruxx');
  });

  it('points to the exact approved public Firebase registration', () => {
    const { expo } = loadJson('app.json') as { expo: { android: { googleServicesFile?: string } } };
    expect(expo.android.googleServicesFile).toBe('./google-services.json');
    const bytes = readFileSync(new URL('google-services.json', mobileRoot));
    expect(createHash('sha256').update(bytes).digest('hex')).toBe('44babffefef9ca11f0de585ec45b5ac1a1f7f80f63328efe1b4fbf9d68a4d10a');
    const registration = JSON.parse(bytes.toString('utf8'));
    expect(registration.project_info).toMatchObject({ project_id: 'samuraiapi-51996', project_number: '762123271201' });
    expect(registration.client).toEqual(expect.arrayContaining([expect.objectContaining({ client_info: expect.objectContaining({ mobilesdk_app_id: '1:762123271201:android:35e9d8498bea4f64113760', android_client_info: { package_name: 'in.fitcruxx.app' } }) })]));
  });

  it('configures the notification plugin once with the agreed default channel', () => {
    const { expo } = loadJson('app.json') as { expo: { plugins: (string | [string, Record<string, unknown>])[] } };
    const plugins = expo.plugins.filter(plugin => (Array.isArray(plugin) ? plugin[0] : plugin) === 'expo-notifications');
    expect(plugins).toEqual([['expo-notifications', expect.objectContaining({ defaultChannel: 'fitcruxx-updates' })]]);
  });

  it('contains no private service account, wakeup credential or server key', () => {
    const config = JSON.stringify(loadJson('app.json')) + JSON.stringify(loadJson('google-services.json'));
    expect(config).not.toMatch(/BEGIN (?:RSA )?PRIVATE KEY|private_key|client_email|service_account|PUSH_DISPATCH_SECRET|FCM_SERVICE_ACCOUNT_JSON|server_key|access_token/i);
  });
});

