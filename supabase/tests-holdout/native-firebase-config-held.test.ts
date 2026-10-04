import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

describe('NFC public Android build contract (independent holdout)', () => {
  const mobile = resolve('apps/mobile');
  const readConfig = () => JSON.parse(readFileSync(resolve(mobile, 'app.json'), 'utf8')).expo;

  it('NFC-001 preserves approved application identity and client file location', () => {
    const config = readConfig();
    expect(config.android.package).toBe('in.fitcruxx.app');
    expect(config.scheme).toBe('fitcruxx');
    expect(config.extra.eas.projectId).toBe('3708f347-96ac-4236-a74c-95808210292b');
    expect(config.android.googleServicesFile).toBe('./google-services.json');
  });

  it('NFC-001 embeds the byte-identical approved public registration', () => {
    const bytes = readFileSync(resolve(mobile, 'google-services.json'));
    expect(createHash('sha256').update(bytes).digest('hex')).toBe('44babffefef9ca11f0de585ec45b5ac1a1f7f80f63328efe1b4fbf9d68a4d10a');
    const registration = JSON.parse(bytes.toString('utf8'));
    expect(registration.project_info.project_id).toBe('samuraiapi-51996');
    expect(registration.project_info.project_number).toBe('762123271201');
    expect(registration.client).toEqual(expect.arrayContaining([expect.objectContaining({
      client_info: expect.objectContaining({
        mobilesdk_app_id: '1:762123271201:android:35e9d8498bea4f64113760',
        android_client_info: { package_name: 'in.fitcruxx.app' },
      }),
    })]));
  });

  it('NFC-002 configures one notifications plugin with the approved default channel', () => {
    const plugins = readConfig().plugins as Array<string | [string, Record<string, unknown>]>;
    const notifications = plugins.filter((plugin) => (Array.isArray(plugin) ? plugin[0] : plugin) === 'expo-notifications');
    expect(notifications).toEqual([['expo-notifications', expect.objectContaining({ defaultChannel: 'fitcruxx-updates' })]]);
  });

  it('NFC-001 keeps server-only credentials out of both native public artifacts', () => {
    const artifacts = [readConfig(), JSON.parse(readFileSync(resolve(mobile, 'google-services.json'), 'utf8'))];
    for (const artifact of artifacts) {
      expect(JSON.stringify(artifact)).not.toMatch(/private_key|service_account|PUSH_DISPATCH_SECRET|FCM_SERVICE_ACCOUNT_JSON|BEGIN (?:RSA )?PRIVATE KEY|server[_-]?key/i);
    }
  });
});
