# Native identity integration — public declarations only

Companion to the frozen native-identity-integration-contract.md. These are
public types and module dependency identities, not source bodies or algorithms.
Authoring may use compiler-generated declarations without implementation bodies.

```ts
// apps/mobile/lib/mobile-context.tsx
type AppearanceMode = 'system' | 'light' | 'dark';
type MobilePalette = (typeof UI_TOKENS.colors)[keyof typeof UI_TOKENS.colors];
type MobileContextValue = {
  api: ApiClient;
  appearance: AppearanceMode;
  identity: GymloopIdentity;
  businessType: BusinessType | null;
  nouns: BusinessNouns;
  palette: MobilePalette;
  ready: boolean;
  session: Session | null;
  supabase: SupabaseClient<Database>;
  setAppearance(mode: AppearanceMode): Promise<void>;
  signOut(): Promise<void>;
  webOrigin: string;
};
declare function MobileProvider(props: { children: ReactNode }): React.JSX.Element;
declare function useMobile(): MobileContextValue;

// apps/mobile/lib/session.ts: public outcome used by native-session.ts
type MobileStartupState = {
  identity: GymloopIdentity;
  queueScope: Pick<Extract<GymloopIdentity, { kind: 'member' }>,
    'userId' | 'tenantId' | 'memberId'> | null;
  replay: 'ready' | 'deferred' | 'blocked';
};

// apps/mobile/lib/native-session.ts: provider-facing exports
declare function createMobileSupabase(config: {
  supabaseUrl: string;
  supabaseAnonKey: string;
}): SupabaseClient<Database>;
declare function resolveNativeMobileSession(
  supabase: SupabaseClient<Database>, session: Session | null,
  isCurrent?: () => boolean,
): Promise<MobileStartupState>;
declare function signOutMobile(supabase: SupabaseClient<Database>): Promise<void>;
```

The provider's current public dependencies include `@gymloop/api-client`,
`@gymloop/shared`, `@supabase/supabase-js` (Session/SupabaseClient types),
`@gymloop/db` (Database type), `@expo-google-fonts/archivo`, `expo-secure-store`,
`expo-splash-screen`, `react-native`, `react`, its two bundled Archivo display
TTFs, `./offline-check-in`, `./native-session`, and `./business-type`.
Additional Shop/announcement dependencies are the integration under test.
No private import graph or private function signatures are required.

Public wire schema/type modules in packages/shared/src/api/shop.ts,
announcements.ts and identity.ts may supply fixture shapes. Do not read helper
bodies. The ANC and Shop callable cache declarations are also specified in
their public proposal/application-interface metadata. The new ANC integration
seam is only `clearAnnouncementCache(): Promise<void>`.
