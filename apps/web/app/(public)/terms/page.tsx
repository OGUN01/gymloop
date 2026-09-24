import type { Metadata } from 'next';
import Link from 'next/link';
import { PRODUCT_NAME, PUBLISHER_NAME, PUBLIC_PAGE_PATHS, SUPPORT_EMAIL } from '@gymloop/shared';

export const metadata: Metadata = { title: `Terms of use | ${PRODUCT_NAME}`, description: `Plain-language terms for using ${PRODUCT_NAME} with your gym.` };

export default function TermsPage() {
  return <main className="public-main">
    <header className="public-intro">
      <p className="cl-eyebrow">Using the service</p>
      <h1 className="cl-title">Terms of use</h1>
      <p className="public-lede">A short explanation of what to expect when your gym uses {PRODUCT_NAME}.</p>
      <p className="public-effective">Effective 24 September 2026 · Operated by {PUBLISHER_NAME}</p>
    </header>
    <section className="public-section" aria-labelledby="terms-service">
      <p className="cl-eyebrow">01 / Your gym</p>
      <h2 id="terms-service" className="cl-section-title">Who provides what</h2>
      <p>{PUBLISHER_NAME} provides {PRODUCT_NAME} to gyms so they can record check-ins, memberships, follow-ups, receipts and add-ons. A member&rsquo;s access depends on their gym linking their account. The gym is responsible for the information it enters, the membership and add-on terms it offers, and its relationship with its members.</p>
      <p>The gym collects money outside {PRODUCT_NAME}. We provide a record of payments and receipts the gym enters; we do not collect or process card or UPI payments for it.</p>
    </section>
    <section className="public-section" aria-labelledby="terms-use">
      <p className="cl-eyebrow">02 / Fair use</p>
      <h2 id="terms-use" className="cl-section-title">Use it respectfully</h2>
      <p>Use only your own account and keep your sign-in details private. Do not access another person&rsquo;s records, enter information you are not allowed to share, interfere with someone else&rsquo;s access, or use the service to send unwanted messages.</p>
      <p>Gym staff should enter accurate information and respond to members&rsquo; questions about their gym&rsquo;s records. If something looks wrong, let your gym know so it can correct it.</p>
    </section>
    <section className="public-section" aria-labelledby="terms-availability">
      <p className="cl-eyebrow">03 / Help</p>
      <h2 id="terms-availability" className="cl-section-title">Availability and contact</h2>
      <p>We work to keep {PRODUCT_NAME} available, but the service is provided as is. We do not promise uninterrupted access. For membership, check-in or payment questions, contact your gym first.</p>
      <p>For a service problem, email <a className="public-text-link" href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a> or see <Link className="public-text-link" href={PUBLIC_PAGE_PATHS.support}>Support</Link>. The <Link className="public-text-link" href={PUBLIC_PAGE_PATHS.privacy}>privacy policy</Link> explains how information is handled.</p>
    </section>
  </main>;
}
