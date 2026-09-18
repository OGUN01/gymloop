import type { Metadata } from 'next';
import { PRODUCT_NAME } from '@gymloop/shared';
import './globals.css';
import { AppThemeProvider } from './theme-provider';
import { ThemeTokenStyle } from './theme-token-style';

export const metadata: Metadata = {
  title: PRODUCT_NAME,
  description: 'Multi-tenant gym retention SaaS.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>
        <ThemeTokenStyle />
        <AppThemeProvider>{children}</AppThemeProvider>
      </body>
    </html>
  );
}
