import * as WebBrowser from 'expo-web-browser';
import { PRODUCT_NAME, PUBLIC_PAGE_PATHS } from '@gymloop/shared';
import { LedgerSection, Row } from './ui';
import { publicPageUrl } from '../lib/public-page';
import { useMobile } from '../lib/mobile-context';

const LEGAL_PAGES = [
  { key: 'privacy', label: 'Privacy policy', path: PUBLIC_PAGE_PATHS.privacy },
  { key: 'delete-account', label: 'Delete my account', path: PUBLIC_PAGE_PATHS.deleteAccount },
] as const;

/**
 * Quiet legal group for Google Play review and members: privacy and account
 * deletion open the matching public web page in the in-app browser. Lives
 * outside the four Account rows (member You keeps exactly those four listitems).
 */
export function LegalLinks() {
  const { webOrigin } = useMobile();
  return <LedgerSection title="Legal">
    {LEGAL_PAGES.map((page) => (
      <Row
        key={page.key}
        title={page.label}
        accessibilityLabel={`${page.label}, opens in your browser`}
        accessibilityHint={`Opens the ${PRODUCT_NAME} website`}
        onPress={() => { void WebBrowser.openBrowserAsync(publicPageUrl(webOrigin, page.path)); }}
      />
    ))}
  </LedgerSection>;
}
