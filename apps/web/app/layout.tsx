import type { Metadata } from 'next';
import { PRODUCT_NAME } from '@gymloop/shared';
import './globals.css';

export const metadata: Metadata = {
  title: PRODUCT_NAME,
  description: 'Multi-tenant gym retention SaaS.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
