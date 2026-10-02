import { createRequire } from 'node:module';
import { defineConfig } from 'vitest/config';

const webRequire = createRequire(new URL('./apps/web/package.json', import.meta.url));
const mobileRequire = createRequire(new URL('./apps/mobile/package.json', import.meta.url));

// Root-held contracts render the actual web boundaries. Match the web JSX transform and
// resolve mocks and consumers to the same installed Next/React module identities.
export default defineConfig({
  test: { include: ['**/*.{test,spec}.{ts,tsx}'] },
  oxc: { jsx: { runtime: 'automatic' } },
  resolve: {
    alias: [
      { find: /^next\/headers$/, replacement: webRequire.resolve('next/headers') },
      { find: /^next\/navigation$/, replacement: webRequire.resolve('next/navigation') },
      { find: /^react$/, replacement: webRequire.resolve('react') },
      { find: /^react\/jsx-runtime$/, replacement: webRequire.resolve('react/jsx-runtime') },
      { find: /^react\/jsx-dev-runtime$/, replacement: webRequire.resolve('react/jsx-dev-runtime') },
      { find: /^react-dom\/server$/, replacement: webRequire.resolve('react-dom/server') },
      ...['react-native', 'expo-router', 'expo-crypto', 'expo-secure-store', 'expo-web-browser', 'expo-network'].map(name => ({ find: new RegExp(`^${name}$`), replacement: mobileRequire.resolve(name) })),
    ],
  },
});
