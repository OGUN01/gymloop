import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

type JsonObject = Record<string, unknown>;

const readJson = (relativePath: string): JsonObject =>
  JSON.parse(readFileSync(new URL(`../../${relativePath}`, import.meta.url), 'utf8')) as JsonObject;

const mobilePackage = readJson('apps/mobile/package.json');
const appConfig = readJson('apps/mobile/app.json');
const easConfig = readJson('apps/mobile/eas.json');

const expo = appConfig.expo as JsonObject;
const android = expo.android as JsonObject;
const plugins = expo.plugins as unknown[];
const cameraPlugin = plugins.find((plugin) => Array.isArray(plugin) && plugin[0] === 'expo-camera') as
  | [string, JsonObject]
  | undefined;
const buildProfiles = (easConfig.build ?? {}) as JsonObject;
const production = (buildProfiles.production ?? {}) as JsonObject;
const productionAndroid = (production.android ?? {}) as JsonObject;

describe('HARD-002 Android release configuration', () => {
  it('@gymloop/mobile runs its tests through a package test script', () => {
    const scripts = mobilePackage.scripts as JsonObject;
    expect(scripts.test, 'apps/mobile/package.json must define a test script').toEqual(expect.any(String));
    expect(String(scripts.test)).toMatch(/vitest|jest|mocha|expo\s+test/);
  });

  it('permits camera access without recording audio', () => {
    const permissions = android.permissions as string[];
    const blockedPermissions = android.blockedPermissions as string[];
    expect(permissions).toContain('android.permission.CAMERA');
    expect(blockedPermissions).toEqual(expect.arrayContaining([
      'android.permission.RECORD_AUDIO',
      'android.permission.SYSTEM_ALERT_WINDOW',
      'android.permission.READ_EXTERNAL_STORAGE',
      'android.permission.WRITE_EXTERNAL_STORAGE',
    ]));
    expect(cameraPlugin?.[1]?.recordAudioAndroid, 'expo-camera must disable Android audio recording').toBe(false);
  });

  it('defines a production Android app-bundle profile for store distribution', () => {
    expect(buildProfiles.production, 'EAS production profile is required').toEqual(expect.any(Object));
    expect(productionAndroid.buildType).toBe('app-bundle');
  });

  it('names the store app Kytros and uses in.kytros.app on Android and iOS', () => {
    expect(expo.name).toBe('Kytros');
    expect(android.package).toBe('in.kytros.app');
    expect((expo.ios as JsonObject).bundleIdentifier).toBe('in.kytros.app');
    expect(cameraPlugin?.[1]?.cameraPermission).toBe('Allow Kytros to scan the current QR code at your gym.');
  });

  it('uses remote EAS versioning and automatically increments production Android releases', () => {
    expect(easConfig.cli?.appVersionSource).toBe('remote');
    expect(production.autoIncrement).toBe(true);
  });

  it('does not make the production profile internal or credential-free', () => {
    expect(production.distribution).not.toBe('internal');
    expect(production.withoutCredentials).not.toBe(true);
    expect(productionAndroid.withoutCredentials).not.toBe(true);
  });
});
