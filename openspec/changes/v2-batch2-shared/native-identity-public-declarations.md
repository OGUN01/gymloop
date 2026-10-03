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
declare function MobileProvider(props: { children: ReactNode }): React.JSX.Element | null;
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

Do not open source modules to obtain wire types: some public exports share
lines/files with helper bodies. Importing their public types in a test is allowed;
use the declarations below for authoring. Ask root for any missing declaration.

```ts
type GymloopIdentity =
  | { kind: 'staff'; userId: string; tenantId: string; staffId: string;
      role: 'gym_owner' | 'gym_manager' | 'front_desk' | 'trainer' }
  | { kind: 'member'; userId: string; tenantId: string; memberId: string }
  | { kind: 'platform'; userId: string; role: 'super_admin' | 'platform_support' }
  | { kind: 'impersonation'; userId: string; tenantId: string; impersonationSessionId: string }
  | { kind: 'unlinked' };

// Public @gymloop/api-client interfaces
type ApiError = { code: string; message: string; [key: string]: unknown };
type ApiEnvelope<T = unknown> = { ok: true; data: T } | { ok: false; error: ApiError };
type ApiFetch = (input: string, init: {
  method: 'POST'; headers: Readonly<Record<string, string>>; body: string;
}) => Promise<{ json(): Promise<unknown> }>;
type ApiClientOptions = { baseUrl: string; accessToken: () => Promise<string | null>; fetch: ApiFetch };
type ApiClient = {
  checkIn(command: CheckInRequest): Promise<ApiEnvelope<CheckInResult>>;
  post<T = unknown>(path: string, body: unknown): Promise<ApiEnvelope<T>>;
};
declare function createApiClient(options: ApiClientOptions): ApiClient;

// apps/mobile/lib/shop-cache.ts
interface ShopCacheStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
  remove(key: string): Promise<void>;
}
declare const nativeShopCache: ShopCacheStore;
declare function shopCacheCurrent(store: ShopCacheStore): () => boolean;
declare function createMemoryShopCache(): ShopCacheStore;
declare function writeShopCache(store: ShopCacheStore, scope: string, response: ShopCatalogueResponse): Promise<void>;
declare function readShopCache(store: ShopCacheStore, scope: string): Promise<{ response: ShopCatalogueResponse; savedAt: string } | null>;
declare function clearShopCache(store?: ShopCacheStore): Promise<void>;
type ShopCatalogueResponse = {
  items: ShopItem[]; reservations: ShopReservation[];
  truncated: boolean; serverTime: string;
};
type ShopItem = {
  itemId: string; section: 'products' | 'services'; name: string;
  description: string; pricePaise: string; currency: 'INR'; gstRateBp: number;
  validityDays: number; cancellationTerms: string; quoteVersion: string;
  categoryId: string | null; categoryName: string | null; imageUrl: string | null;
  availability: 'available' | 'out_of_stock'; availableQuantity: number | null;
};

// apps/mobile/lib/announcements.ts
declare const ANNOUNCEMENT_CACHE_KEY: 'gymloop.announcements-cache';
type AnnouncementScope = { tenantId: string; userId: string; memberId: string };
type CachedFeed = {
  scope: AnnouncementScope; fetchedAt: string; announcements: AnnouncementCard[];
  pendingReads: Array<{ announcementId: string; versionNo: number }>;
};
type AnnouncementCard = {
  announcementId: string; kind: 'transactional' | 'promotional'; title: string;
  body: string; imageUrl: string | null; versionNo: number; publishedAt: string;
  editedAt: string | null; expiresAt: string | null; changeNote: string | null;
  readState: 'unread' | 'updated' | 'read'; readAt: string | null;
};
declare function loadAnnouncementCache(scope: AnnouncementScope): Promise<CachedFeed | null>;
declare function saveAnnouncementCache(cache: CachedFeed, isCurrent?: () => boolean): Promise<void>;
declare function queueRead(scope: AnnouncementScope, announcementId: string, versionNo: number, isCurrent?: () => boolean): Promise<void>;
declare function flushPendingReads(api: ApiClient, scope: AnnouncementScope, isCurrent?: () => boolean): Promise<void>;
declare function resolveAnnouncementFeed(input: {
  fetched: AnnouncementCard[] | null; cached: CachedFeed | null; scope: AnnouncementScope;
}): { cards: AnnouncementCard[]; stale: boolean; fetchedAt: string | null };
declare function applyLocalRead(cards: AnnouncementCard[], announcementId: string, versionNo: number): AnnouncementCard[];
declare function clearAnnouncementCache(): Promise<void>; // New integration seam

// Other existing provider dependency declarations
declare function clearOfflineCheckIns(): Promise<void>;
declare const BUSINESS_TYPE_STORAGE_KEY: 'gymloop.business-type';
declare function encodePersistedBusinessType(tenantId: string, type: BusinessType): string;
declare function readPersistedBusinessType(raw: string | null, tenantId: string): BusinessType | null;
declare function resolveBusinessType(input: { fetched: BusinessType | null; persisted: BusinessType | null }): BusinessType | null;
```

Fixture constraints: IDs must be valid UUIDs, non-null dates must be ISO instants
with offsets, paise strings must be nonnegative canonical digits, and titles/
bodies/item descriptions/terms must be nonempty. Empty Shop reservations are valid.
This packet describes names/shapes only and does not add a claim parser or
require a new authentication gate.
